defmodule Bilimbi.Base.Database.QueryExecutorTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.QueryExecutor

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
