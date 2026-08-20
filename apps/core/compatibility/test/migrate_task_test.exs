defmodule Mix.Tasks.Bilimbi.MigrateTest do
  use ExUnit.Case, async: false

  @package_root Path.expand("..", __DIR__)

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

  defp qualified(schema, table) do
    "#{SchemaVerifier.quote_identifier!(schema)}.#{SchemaVerifier.quote_identifier!(table)}"
  end
end
