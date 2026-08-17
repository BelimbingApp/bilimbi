defmodule Bilimbi.Core.PlatformBaselineE2ETest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnostics
  alias Bilimbi.Core.Compatibility.PlatformBaselineTestRepo
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @package_root Path.expand("..", __DIR__)

  setup context do
    PlatformBaselineFailureDiagnostics.capture(context, :setup, fn ->
      repo_options =
        Repo.config()
        |> Keyword.put(:name, MigrationTestRepo)
        |> Keyword.put(:pool, DBConnection.ConnectionPool)
        |> Keyword.put(:pool_size, 4)

      Application.put_env(:bilimbi_base_database, MigrationTestRepo, repo_options)

      on_exit(fn ->
        PlatformBaselineFailureDiagnostics.capture(context, :cleanup, fn ->
          Application.delete_env(:bilimbi_base_database, MigrationTestRepo)
        end)
      end)

      start_supervised!(MigrationTestRepo)

      partition =
        "bilimbi_e2e_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

      database = "bilimbi_test_#{partition}"
      quoted_database = SchemaVerifier.quote_identifier!(database)

      SQL.query!(MigrationTestRepo, "CREATE DATABASE #{quoted_database}", [])

      on_exit(fn ->
        PlatformBaselineFailureDiagnostics.capture(context, :cleanup, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            SQL.query!(Repo, "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)", [])
          end)
        end)
      end)

      platform_repo_options =
        Repo.config()
        |> Keyword.put(:name, PlatformBaselineTestRepo)
        |> Keyword.put(:database, database)
        |> Keyword.put(:pool, DBConnection.ConnectionPool)
        |> Keyword.put(:pool_size, 1)

      Application.put_env(
        :bilimbi_base_database,
        PlatformBaselineTestRepo,
        platform_repo_options
      )

      on_exit(fn ->
        PlatformBaselineFailureDiagnostics.capture(context, :cleanup, fn ->
          Application.delete_env(:bilimbi_base_database, PlatformBaselineTestRepo)
        end)
      end)

      start_supervised!(PlatformBaselineTestRepo)
      assert PlatformBaselineTestRepo.config()[:pool_size] == 1

      %{env: [{"MIX_TEST_PARTITION", "_#{partition}"}]}
    end)
  end

  test "the operational fresh install verifies and supports the public identity APIs",
       %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert recorded_versions() == Enum.map(Compatibility.migration_entries(), &elem(&1, 0))

      assert run_mix!(
               "run",
               ["-e", "Bilimbi.Core.Compatibility.PlatformBaselineSmoke.run()"],
               env
             ) =~ "Platform baseline public API smoke passed."
    end)
  end

  test "the operational adoption command refuses drift without creating a ledger",
       %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      SQL.query!(
        PlatformBaselineTestRepo,
        "DROP TABLE bilimbi_schema_migrations",
        []
      )

      SQL.query!(
        PlatformBaselineTestRepo,
        "ALTER TABLE companies DROP COLUMN legal_name",
        []
      )

      {output, status} = run_mix("bilimbi.schema.adopt", [], env)

      assert status != 0
      assert output =~ "Schema adoption refused because drift was detected"
      assert output =~ "companies: missing column legal_name"
      assert relation("bilimbi_schema_migrations") == nil
    end)
  end

  test "the production seed command records real reference data once", %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      required_seed_ids = ["base/authz/system-roles", "core/employee/system-types"]
      first_output = run_mix!("bilimbi.seeds.run", [], env)
      second_output = run_mix!("bilimbi.seeds.run", [], env)

      Enum.each(required_seed_ids, fn seed_id ->
        assert first_output =~ "completed: #{seed_id}"
        assert second_output =~ "skipped: #{seed_id}"
      end)

      runs =
        Database.list_production_seed_runs(repo: PlatformBaselineTestRepo)
        |> Map.new(&{&1.id, &1})

      Enum.each(required_seed_ids, fn seed_id ->
        assert %{status: :completed, attempts: 1} = Map.fetch!(runs, seed_id)
      end)

      assert [[5]] =
               SQL.query!(
                 PlatformBaselineTestRepo,
                 "SELECT count(*) FROM employee_types WHERE is_system",
                 []
               ).rows
    end)
  end

  defp run_mix!(task, args, env) do
    case run_mix(task, args, env) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("mix #{task} failed with status #{status}:\n#{output}")
    end
  end

  defp run_mix(task, args, env) do
    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        [task | args],
        cd: @package_root,
        env: [{"MIX_ENV", "test"} | env],
        stderr_to_stdout: true
      )

    PlatformBaselineFailureDiagnostics.record_nested_mix(task, args, status, output)
    {output, status}
  end

  defp recorded_versions do
    SQL.query!(
      PlatformBaselineTestRepo,
      "SELECT version FROM bilimbi_schema_migrations ORDER BY version",
      []
    ).rows
    |> Enum.map(fn [version] -> version end)
  end

  defp relation(table) do
    [[relation]] =
      SQL.query!(PlatformBaselineTestRepo, "SELECT to_regclass($1)::text", [table]).rows

    relation
  end
end
