defmodule Bilimbi.Base.Database.ConsoleAccessTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ConsoleAccess
  alias Bilimbi.Base.Database.ConsoleRepo
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  # Base Database's own test project installs no persistence owner, so the
  # declared reads come from this contract; the installed contracts' effect is
  # observed by apps/core/compatibility/test/migrate_task_test.exs.
  defmodule ProbeContract do
    @behaviour Bilimbi.Base.Database.SchemaContract

    @impl true
    def tables, do: Enum.map(~w(users sessions companies), &%{name: &1})

    @impl true
    def secret_columns do
      %{"users" => ["password", "remember_token"], "sessions" => ["payload"]}
    end
  end

  defmodule AbsentTableContract do
    @behaviour Bilimbi.Base.Database.SchemaContract

    @impl true
    def tables, do: []

    @impl true
    def secret_columns, do: %{"not_migrated_yet" => ["token"]}
  end

  defmodule MistypedContract do
    @behaviour Bilimbi.Base.Database.SchemaContract

    @impl true
    def tables, do: [%{name: "users"}]

    @impl true
    def secret_columns, do: %{"users" => ["password_hash"]}
  end

  @reconcile [contracts: [ProbeContract]]

  # The console connects through its own login and sees only committed state:
  # nothing this test creates inside the sandbox transaction, and nothing in
  # another session's temporary schema. The probe schema therefore lives
  # outside the sandbox, carries the installed contracts' table names, and is
  # dropped afterwards. Reconciliation runs outside the sandbox too, so the
  # grants it makes are what the console connection then observes.
  setup do
    schema = "blb_console_probe_#{System.unique_integer([:positive])}"
    quoted = SchemaVerifier.quote_identifier!(schema)
    role = SchemaVerifier.quote_identifier!(ConsoleAccess.role_name())

    committed!(fn ->
      SQL.query!(Repo, "CREATE SCHEMA #{quoted}", [])
      SQL.query!(Repo, "GRANT USAGE ON SCHEMA #{quoted} TO #{role}", [])

      SQL.query!(
        Repo,
        "CREATE TABLE #{quoted}.users (id bigint, name text, password text, remember_token text)",
        []
      )

      SQL.query!(Repo, "INSERT INTO #{quoted}.users VALUES (1, 'Ada', 'hash', 'token')", [])

      SQL.query!(
        Repo,
        "CREATE TABLE #{quoted}.sessions (id text, payload text, last_activity integer)",
        []
      )

      SQL.query!(Repo, "INSERT INTO #{quoted}.sessions VALUES ('s1', 'opaque', 7)", [])
      SQL.query!(Repo, "CREATE TABLE #{quoted}.companies (id bigint, name text)", [])
      SQL.query!(Repo, "INSERT INTO #{quoted}.companies VALUES (1, 'Acme')", [])
      SQL.query!(Repo, "CREATE TABLE #{quoted}.laravel_leftover (id bigint)", [])
      SQL.query!(Repo, "CREATE SEQUENCE #{quoted}.leftover_seq", [])

      # Privileges a hand grant left behind, which reconciliation must take back.
      SQL.query!(Repo, "GRANT SELECT, INSERT ON #{quoted}.laravel_leftover TO #{role}", [])
      SQL.query!(Repo, "GRANT UPDATE ON #{quoted}.leftover_seq TO #{role}", [])
      SQL.query!(Repo, "GRANT INSERT, DELETE ON #{quoted}.companies TO #{role}", [])
      SQL.query!(Repo, "GRANT SELECT ON #{quoted}.users TO #{role}", [])
    end)

    on_exit(fn ->
      committed!(fn -> SQL.query!(Repo, "DROP SCHEMA #{quoted} CASCADE", []) end)
    end)

    %{schema: schema, quoted: quoted}
  end

  describe "reconcile/2" do
    test "grants SELECT on every table minus secret columns and revokes everything else", %{
      schema: schema,
      quoted: quoted
    } do
      assert {:ok, summary} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo, [prefix: schema] ++ @reconcile)
               end)

      assert summary.role == ConsoleAccess.role_name()
      assert summary.tables == 4
      assert summary.restricted == ["sessions", "users"]
      assert summary.absent == []

      # Observed through the console connection, not the catalog.
      assert console("SELECT id, name FROM #{quoted}.users") == {:ok, [[1, "Ada"]]}
      assert console("SELECT id, last_activity FROM #{quoted}.sessions") == {:ok, [["s1", 7]]}
      assert console("SELECT * FROM #{quoted}.companies") == {:ok, [[1, "Acme"]]}
      assert console("SELECT * FROM #{quoted}.laravel_leftover") == {:ok, []}

      for sql <- [
            "SELECT password FROM #{quoted}.users",
            "SELECT remember_token FROM #{quoted}.users",
            "SELECT * FROM #{quoted}.users",
            "SELECT payload FROM #{quoted}.sessions",
            "SELECT nextval('#{quoted}.leftover_seq')",
            "SELECT setval('#{quoted}.leftover_seq', 9)",
            "INSERT INTO #{quoted}.companies VALUES (2, 'Refused')",
            "INSERT INTO #{quoted}.laravel_leftover VALUES (2)",
            "DELETE FROM #{quoted}.companies"
          ] do
        assert {:error, :insufficient_privilege} = console(sql), sql
      end
    end

    test "is idempotent", %{schema: schema} do
      assert {:ok, first} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo, [prefix: schema] ++ @reconcile)
               end)

      assert {:ok, ^first} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo, [prefix: schema] ++ @reconcile)
               end)
    end

    test "reports secrets declared on a table the prefix does not hold", %{schema: schema} do
      assert {:ok, summary} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo,
                   prefix: schema,
                   contracts: [AbsentTableContract]
                 )
               end)

      assert summary.absent == ["not_migrated_yet"]
      assert summary.restricted == []
      assert ConsoleAccess.describe(summary) =~ "absent tables: not_migrated_yet"
    end

    test "rejects a secret column the table does not have, changing nothing", %{
      schema: schema,
      quoted: quoted
    } do
      assert {:error, {:unknown_secret_column, "users", "password_hash"} = failure} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo,
                   prefix: schema,
                   contracts: [MistypedContract]
                 )
               end)

      assert ConsoleAccess.explain(failure) =~ ~s(has no column "password_hash")

      # The transaction rolled back: the hand grants from setup still stand.
      assert {:ok, _rows} = console("INSERT INTO #{quoted}.laravel_leftover VALUES (2)")
    end

    test "refuses when the console role does not exist", %{schema: schema} do
      configure_console_role!("blb_absent_console_role")

      assert {:error, {:role_missing, "blb_absent_console_role"} = failure} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo, [prefix: schema] ++ @reconcile)
               end)

      assert ConsoleAccess.explain(failure) =~ ~s(CREATE ROLE "blb_absent_console_role" LOGIN)
      assert ConsoleAccess.explain(failure) =~ "mix bilimbi.migrate"
    end

    test "refuses when the console role is the application's own login", %{schema: schema} do
      login = Repo.config()[:username]
      configure_console_role!(login)

      assert {:error, {:role_is_application_login, ^login} = failure} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo, [prefix: schema] ++ @reconcile)
               end)

      assert ConsoleAccess.explain(failure) =~ "application's own database login"
    end
  end

  describe "held_write_privileges/1" do
    test "is empty for the console connection and names what the application login holds", %{
      schema: schema
    } do
      assert {:ok, _summary} =
               committed!(fn ->
                 Database.reconcile_console_access(Repo, [prefix: schema] ++ @reconcile)
               end)

      assert %{reasons: []} = ConsoleAccess.held_write_privileges(ConsoleRepo)

      # The application login owns the database, so it may create schemas in
      # it; that alone is enough for the console to refuse to run through it.
      assert %{role: role, reasons: reasons} =
               committed!(fn -> ConsoleAccess.held_write_privileges(Repo) end)

      assert role == Repo.config()[:username]
      assert "may create schemas" in reasons
    end
  end

  defp console(sql) do
    case SQL.query(ConsoleRepo, sql, []) do
      {:ok, %{rows: rows}} -> {:ok, rows}
      {:error, %Postgrex.Error{postgres: %{code: code}}} -> {:error, code}
    end
  end

  # `role_name/0` reads the console Repo's configuration at call time; the
  # running connection is untouched.
  defp configure_console_role!(role) do
    config = Application.fetch_env!(:bilimbi_base_database, ConsoleRepo)
    Application.put_env(:bilimbi_base_database, ConsoleRepo, Keyword.put(config, :username, role))
    on_exit(fn -> Application.put_env(:bilimbi_base_database, ConsoleRepo, config) end)
  end

  defp committed!(fun), do: Sandbox.unboxed_run(Repo, fun)
end
