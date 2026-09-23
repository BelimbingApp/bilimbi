defmodule Bilimbi.Base.Database.QueryExecutorTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ConsoleAccess
  alias Bilimbi.Base.Database.ConsoleRepo
  alias Bilimbi.Base.Database.QueryExecutor
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  describe "extract_named_parameters/1" do
    test "extracts named parameters" do
      sql = "SELECT * FROM users WHERE status = :status AND age > :min_age"
      assert QueryExecutor.extract_named_parameters(sql) == ["status", "min_age"]
    end

    test "ignores parameters inside string literals" do
      sql = "SELECT ':not_a_param' AS val, * FROM users WHERE status = :status"
      assert QueryExecutor.extract_named_parameters(sql) == ["status"]
    end

    test "ignores PostgreSQL type casts like ::int" do
      sql = "SELECT id::int FROM users WHERE id = :user_id"
      assert QueryExecutor.extract_named_parameters(sql) == ["user_id"]
    end

    test "ignores comments" do
      sql = """
      -- Comment with :ignored_1
      /* Block comment with :ignored_2 */
      SELECT * FROM users WHERE active = :active
      """

      assert QueryExecutor.extract_named_parameters(sql) == ["active"]
    end
  end

  # #650: the engine is operator-only tooling and fails closed unless the caller
  # asserts the platform-operator tenant. These tests exercise the SQL contract
  # as the operator; the "operator gate" describe below covers the guard itself.
  defp as_operator(sql, params \\ %{}, opts \\ []) do
    Database.execute_readonly(sql, params, Keyword.put(opts, :operator, true))
  end

  defp committed!(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)

  describe "execute_readonly/3" do
    test "executes simple select query" do
      assert {:ok, result} = as_operator("SELECT 1 AS num, 'test' AS label")
      assert result.columns == ["num", "label"]
      assert result.rows == [%{"num" => 1, "label" => "test"}]
      assert result.total == 1
      assert result.page == 1
      assert result.per_page == 25
      assert result.last_page == 1
    end

    test "executes query with named parameters" do
      sql = "SELECT :greeting || ', ' || :name AS msg"
      params = %{"greeting" => "Hello", "name" => "World"}

      assert {:ok, result} = as_operator(sql, params)
      assert result.rows == [%{"msg" => "Hello, World"}]
    end

    test "executes query with WITH clause" do
      sql = "WITH vals AS (SELECT 42 AS answer) SELECT answer * 2 AS doubled FROM vals"

      assert {:ok, result} = as_operator(sql)
      assert result.rows == [%{"doubled" => 84}]
    end

    test "binds atom-keyed params and preserves a false value" do
      sql = "SELECT :flag::boolean AS flag"

      assert {:ok, result} = as_operator(sql, %{flag: false})
      assert result.rows == [%{"flag" => false}]
    end

    test "does not mint atoms from SQL-authored parameter names" do
      # The discriminating shape is a parameter that appears in the SQL but is
      # ABSENT from the params map: the old code's `||` chain only reached
      # String.to_atom/1 on that miss, so a present key never minted anything.
      # Warm the execution path first so lazy module loading cannot skew the
      # atom count; the measured call must then create zero atoms even though
      # its parameter name has never been seen by this VM.
      assert {:ok, _} = as_operator("SELECT :warm::text AS v", %{"warm" => "x"})

      atom_count_before = :erlang.system_info(:atom_count)
      param = "zz_#{System.unique_integer([:positive])}"

      assert {:ok, _} = as_operator("SELECT :#{param}::text AS v", %{})

      assert :erlang.system_info(:atom_count) == atom_count_before
    end

    test "supports pagination and sorting" do
      sql = "SELECT generate_series(1, 10) AS num"

      assert {:ok, result} =
               as_operator(sql, %{},
                 page: 2,
                 per_page: 3,
                 order_by: "num",
                 order_dir: :desc
               )

      assert result.total == 10
      assert result.page == 2
      assert result.per_page == 3
      assert result.last_page == 4
      assert result.rows == [%{"num" => 7}, %{"num" => 6}, %{"num" => 5}]
    end

    test "rejects empty SQL" do
      assert {:error, "Query cannot be empty."} = as_operator("   ")
    end

    test "rejects non-SELECT/WITH statements" do
      assert {:error, "Only SELECT or WITH queries are permitted."} =
               as_operator("SET search_path TO public")
    end

    test "rejects write / DDL keywords" do
      assert {:error, "Write or DDL statements are not permitted in queries."} =
               as_operator("SELECT * FROM users; DROP TABLE users;")

      assert {:error, "Only SELECT or WITH queries are permitted."} =
               as_operator("INSERT INTO users (name) VALUES ('attacker')")

      assert {:error, "Only SELECT or WITH queries are permitted."} =
               as_operator("UPDATE users SET name = 'attacker'")

      assert {:error, "Only SELECT or WITH queries are permitted."} =
               as_operator("DELETE FROM users")
    end

    test "handles syntax errors gracefully" do
      assert {:error, msg} = as_operator("SELECT * FROM non_existent_table_xyz")
      assert msg =~ "does not exist" or msg =~ "SQL error"
    end
  end

  # The string guards (SELECT/WITH first word, forbidden keywords) are text
  # checks over user-authored SQL and are not the boundary. The boundary is
  # the console connection's PostgreSQL role, which holds SELECT and nothing
  # else, so these tests prove it by observing the database, never a setting.
  #
  # The console sees only committed state, so every probe object is created
  # outside the sandbox transaction and dropped afterwards.
  describe "database-enforced boundary" do
    setup do
      suffix = System.unique_integer([:positive])
      role = SchemaVerifier.quote_identifier!(ConsoleAccess.role_name())
      sequence = "__blb_console_probe_seq_#{suffix}"
      writable = "__blb_console_writable_#{suffix}"
      partial = "__blb_console_partial_#{suffix}"
      hidden = "__blb_console_hidden_#{suffix}"

      committed!(fn ->
        Repo.query!("CREATE SEQUENCE #{sequence} START 1")
        Repo.query!("CREATE TABLE #{writable} (id integer)")
        Repo.query!("CREATE TABLE #{partial} (id integer, secret text)")
        Repo.query!("INSERT INTO #{partial} VALUES (1, 'hidden')")
        Repo.query!("GRANT SELECT (id) ON #{partial} TO #{role}")
        Repo.query!("CREATE TABLE #{hidden} (id integer)")
      end)

      on_exit(fn ->
        committed!(fn ->
          Repo.query!("DROP SEQUENCE IF EXISTS #{sequence}")
          Repo.query!("DROP TABLE IF EXISTS #{writable}, #{partial}, #{hidden}")
        end)
      end)

      %{role: role, sequence: sequence, writable: writable, partial: partial, hidden: hidden}
    end

    test "runs as the console's own role, not the application's login" do
      assert {:ok, result} = as_operator("SELECT current_user::text AS role")
      assert result.rows == [%{"role" => ConsoleAccess.role_name()}]
      refute ConsoleAccess.role_name() == Repo.config()[:username]
    end

    test "the executor's transaction is read-only as PostgreSQL sees it" do
      assert {:ok, result} =
               as_operator("SELECT current_setting('transaction_read_only') AS mode")

      assert result.rows == [%{"mode" => "on"}]
    end

    test "PostgreSQL refuses, on privileges, a write that passes both text guards", %{
      sequence: sequence
    } do
      # `SELECT setval(...)` starts with SELECT and contains no forbidden
      # keyword, so it reaches PostgreSQL, which checks the role's UPDATE
      # privilege on the sequence before it checks the transaction mode. The
      # refusal names the privilege, not the read-only transaction. setval/2 is
      # also non-transactional: had it run, the new value would survive, so an
      # unchanged sequence proves the write never executed.
      assert {:error, msg} = as_operator("SELECT setval('#{sequence}', 42)")
      assert msg =~ "permission denied for sequence #{sequence}"
      refute msg =~ "read-only transaction"

      assert %{rows: [[1, false]]} =
               committed!(fn -> Repo.query!("SELECT last_value, is_called FROM #{sequence}") end)
    end

    test "the console connection cannot write even outside the executor", %{
      writable: table
    } do
      # No executor, no text guards, and a read-write transaction opened on
      # purpose: only the role's privileges stand, and they are enough.
      assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
               ConsoleRepo.transaction(fn ->
                 SQL.query!(ConsoleRepo, "SET TRANSACTION READ WRITE", [])

                 case SQL.query(ConsoleRepo, "INSERT INTO #{table} VALUES (1)", []) do
                   {:error, error} -> ConsoleRepo.rollback(error)
                   {:ok, result} -> result
                 end
               end)

      assert %{rows: [[0]]} = committed!(fn -> Repo.query!("SELECT count(*) FROM #{table}") end)
    end

    test "refuses to run at all while its connection could write", %{
      role: role,
      sequence: sequence,
      writable: table
    } do
      committed!(fn -> Repo.query!("GRANT INSERT ON #{table} TO #{role}") end)

      assert {:error, msg} = as_operator("SELECT 1")
      assert msg =~ "cannot run because its connection can write"
      assert msg =~ "may write public.#{table}"

      committed!(fn -> Repo.query!("REVOKE INSERT ON #{table} FROM #{role}") end)

      assert {:ok, %{rows: [%{"?column?" => 1}]}} = as_operator("SELECT 1")

      committed!(fn -> Repo.query!("GRANT UPDATE (id) ON #{table} TO #{role}") end)

      assert {:error, msg} = as_operator("SELECT 1")
      assert msg =~ "may write public.#{table}"

      committed!(fn -> Repo.query!("REVOKE UPDATE (id) ON #{table} FROM #{role}") end)

      assert {:ok, %{rows: [%{"?column?" => 1}]}} = as_operator("SELECT 1")

      committed!(fn -> Repo.query!("GRANT USAGE ON SEQUENCE #{sequence} TO #{role}") end)

      assert {:error, msg} = as_operator("SELECT 1")
      assert msg =~ "may write public.#{sequence}"

      committed!(fn -> Repo.query!("REVOKE USAGE ON SEQUENCE #{sequence} FROM #{role}") end)

      assert {:ok, %{rows: [%{"?column?" => 1}]}} = as_operator("SELECT 1")
    end

    test "names the readable columns when SELECT * hits a column-restricted table", %{
      partial: partial,
      hidden: hidden
    } do
      assert {:error, msg} = as_operator("SELECT * FROM #{partial}")
      assert msg =~ "permission denied for table #{partial}"
      assert msg =~ ~s(can read only these columns of "#{partial}": id. Name them instead of *.)

      assert {:ok, result} = as_operator("SELECT id FROM #{partial}")
      assert result.rows == [%{"id" => 1}]

      assert {:error, msg} = as_operator("SELECT id FROM #{hidden}")
      assert msg =~ ~s(has no read access to "#{hidden}")
    end
  end

  describe "operator gate (#650)" do
    test "fails closed when the operator tenant is not asserted" do
      # The gate runs before SQL validation, so even a well-formed SELECT is
      # refused, and the refusal never depends on query shape.
      assert {:error, msg} = Database.execute_readonly("SELECT 1")
      assert msg =~ "platform operator"

      assert {:error, ^msg} = Database.execute_readonly("SELECT 1", %{}, operator: false)
    end

    test "runs the same well-formed query once the operator is asserted" do
      assert {:ok, result} = Database.execute_readonly("SELECT 1 AS n", %{}, operator: true)
      assert result.rows == [%{"n" => 1}]
    end

    test "refuses before reaching the store, so an invalid query still fails closed" do
      # A query that would error at Postgres if the gate ever let it through:
      # the operator error, not the DB error, proves the store was never reached.
      assert {:error, msg} =
               Database.execute_readonly("SELECT * FROM __blb_absent_table_650", %{},
                 operator: false
               )

      assert msg =~ "platform operator"
      refute msg =~ "does not exist"
    end
  end
end
