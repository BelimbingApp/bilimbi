defmodule Mix.Tasks.Bilimbi.MigrateTest do
  use ExUnit.Case, async: false

  @package_root Path.expand("..", __DIR__)

  alias Bilimbi.Base.Database.ConsoleAccess
  alias Bilimbi.Base.Database.ConsoleRepo
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Ecto.Adapters.SQL

  setup do
    repo_options =
      Repo.config()
      |> Keyword.put(:name, MigrationTestRepo)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)

    Application.put_env(:bilimbi_base_database, MigrationTestRepo, repo_options)

    on_exit(fn ->
      Application.delete_env(:bilimbi_base_database, MigrationTestRepo)
    end)

    start_supervised!(MigrationTestRepo)

    schema =
      "bilimbi_migrate_task_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    SQL.query!(MigrationTestRepo, "CREATE SCHEMA #{SchemaVerifier.quote_identifier!(schema)}", [])

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Bilimbi.Base.Repo, fn ->
        SQL.query!(
          Bilimbi.Base.Repo,
          "DROP SCHEMA IF EXISTS #{SchemaVerifier.quote_identifier!(schema)} CASCADE",
          []
        )
      end)
    end)

    %{schema: schema}
  end

  test "operational task runs a pending Bilimbi-only migration across a class-valid gap", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      "DROP TABLE #{qualified(schema, "bilimbi_schema_migrations")}",
      []
    )

    synthetic_version = install_synthetic_migration!()

    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
    assert relation(MigrationTestRepo, schema, "bilimbi_only_task_probe") == nil

    pending =
      Compatibility.migration_entries()
      |> Enum.filter(&(elem(&1, 2) == :bilimbi_only))
      |> Enum.map(&elem(&1, 0))

    assert Mix.Tasks.Bilimbi.Migrate.run(
             ["--prefix", schema, "--quiet"],
             MigrationTestRepo
           ) == pending

    assert relation(MigrationTestRepo, schema, "bilimbi_only_task_probe") != nil
    assert synthetic_version in recorded_versions(MigrationTestRepo, schema)
  end

  test "operational task grants the SQL console role its reads from the installed contracts", %{
    schema: schema
  } do
    Mix.Tasks.Bilimbi.Migrate.run(["--prefix", schema, "--quiet"], MigrationTestRepo)

    role = ConsoleAccess.role_name()
    users = qualified(schema, "users")
    sessions = qualified(schema, "sessions")
    companies = qualified(schema, "companies")

    assert column_privilege?(role, users, "email")
    refute column_privilege?(role, users, "password")
    refute column_privilege?(role, users, "remember_token")
    refute column_privilege?(role, sessions, "payload")
    assert column_privilege?(role, sessions, "user_agent")
    assert table_privilege?(role, companies, "SELECT")
    assert table_privilege?(role, qualified(schema, "bilimbi_schema_migrations"), "SELECT")
    # A Bilimbi-only table no compatibility contract pins is readable too.
    assert table_privilege?(role, qualified(schema, "base_schedule_occurrences"), "SELECT")

    for table <- [users, sessions, companies], privilege <- ~w(INSERT UPDATE DELETE TRUNCATE) do
      refute table_privilege?(role, table, privilege), "#{table} #{privilege}"
    end
  end

  test "operational task stops with instructions when the console role does not exist", %{
    schema: schema
  } do
    config = Application.fetch_env!(:bilimbi_base_database, ConsoleRepo)

    Application.put_env(
      :bilimbi_base_database,
      ConsoleRepo,
      Keyword.put(config, :username, "blb_absent_console_role")
    )

    on_exit(fn -> Application.put_env(:bilimbi_base_database, ConsoleRepo, config) end)

    assert_raise Mix.Error, ~r/CREATE ROLE "blb_absent_console_role" LOGIN/, fn ->
      Mix.Tasks.Bilimbi.Migrate.run(["--prefix", schema, "--quiet"], MigrationTestRepo)
    end

    # The migrations themselves had already run; only the grants are missing.
    assert relation(MigrationTestRepo, schema, "users") != nil
  end

  test "operational task rejects unsupported and positional arguments" do
    assert_raise OptionParser.ParseError, ~r/Unknown option/, fn ->
      Mix.Tasks.Bilimbi.Migrate.run(["--step", "1"], MigrationTestRepo)
    end

    assert_raise Mix.Error, ~r/unexpected arguments: extra/, fn ->
      Mix.Tasks.Bilimbi.Migrate.run(["extra"], MigrationTestRepo)
    end
  end

  test "schema lifecycle tasks load configuration without starting runtime applications" do
    task_sources =
      ~w(
        bilimbi.migrate.ex
        bilimbi.migrations.ex
        bilimbi.rollback.ex
        bilimbi.schema.verify.ex
        bilimbi.schema.adopt.ex
      )

    Enum.each(task_sources, fn filename ->
      source =
        @package_root
        |> Path.join("lib/mix/tasks/#{filename}")
        |> File.read!()

      assert source =~ ~s(@requirements ["app.config"]), filename
      refute source =~ ~s(@requirements ["app.start"]), filename
    end)
  end

  defp install_synthetic_migration! do
    app = :bilimbi_core_compatibility
    version = 20_260_812_000_000
    descriptor = Application.fetch_env!(app, :bilimbi_module)
    suffix = System.unique_integer([:positive, :monotonic])
    relative_path = "test_migrations_#{suffix}"
    path = Application.app_dir(app, relative_path)
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "20260812000000_create_bilimbi_only_task_probe.exs"),
      """
      defmodule Bilimbi.Core.Compatibility.TestMigrations.CreateBilimbiOnlyTaskProbe#{suffix} do
        use Ecto.Migration

        def change do
          create table(:bilimbi_only_task_probe, primary_key: false) do
            add :id, :bigserial, primary_key: true
          end
        end
      end
      """
    )

    test_descriptor =
      descriptor
      |> Map.put(:migrations, relative_path)
      |> Map.put(:migration_dispositions, %{version => :bilimbi_only})

    Application.put_env(app, :bilimbi_module, test_descriptor)

    on_exit(fn ->
      Application.put_env(app, :bilimbi_module, descriptor)
      File.rm_rf!(path)
    end)

    version
  end

  defp relation(repo, schema, table) do
    [[relation]] = SQL.query!(repo, "SELECT to_regclass($1)::text", ["#{schema}.#{table}"]).rows
    relation
  end

  defp recorded_versions(repo, schema) do
    SQL.query!(
      repo,
      "SELECT version FROM #{qualified(schema, "bilimbi_schema_migrations")} ORDER BY version",
      []
    ).rows
    |> Enum.map(fn [version] -> version end)
  end

  defp column_privilege?(role, table, column) do
    [[held?]] =
      SQL.query!(
        MigrationTestRepo,
        "SELECT has_column_privilege($1::text::name, $2::text::regclass, $3::text, 'SELECT')",
        [role, table, column]
      ).rows

    held?
  end

  defp table_privilege?(role, table, privilege) do
    [[held?]] =
      SQL.query!(
        MigrationTestRepo,
        "SELECT has_table_privilege($1::text::name, $2::text::regclass, $3::text)",
        [role, table, privilege]
      ).rows

    held?
  end

  defp qualified(schema, table) do
    "#{SchemaVerifier.quote_identifier!(schema)}.#{SchemaVerifier.quote_identifier!(table)}"
  end
end
