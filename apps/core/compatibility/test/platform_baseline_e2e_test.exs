defmodule Bilimbi.Core.PlatformBaselineE2ETest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

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

      %{
        env: [
          {"MIX_TEST_PARTITION", "_#{partition}"},
          {"BILIMBI_RUNTIME_SCHEMA_FIXTURE", "enabled"}
        ]
      }
    end)
  end

  test "the operational fresh install verifies and supports the public identity APIs",
       %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      assert_runtime_start_fails!(env, :queue)
      assert run_mix!("bilimbi.migrations", [], env) =~ "down"

      run_mix!("bilimbi.migrate", ["--quiet"], env)
      run_mix!("app.start", [], env)

      assert relation("oban_jobs") == "oban_jobs"
      assert oban_migrated_version() == 14

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert recorded_versions() == Enum.map(Compatibility.migration_entries(), &elem(&1, 0))

      recovery_entries =
        Compatibility.migration_entries()
        |> Enum.drop_while(fn {_version, module, _disposition} ->
          module != Bilimbi.Core.Employee.Migrations.BroadenGlobalIndexAndAddSystemCompanyCheck
        end)

      recovery_versions = Enum.map(recovery_entries, &elem(&1, 0))

      SQL.query!(
        PlatformBaselineTestRepo,
        "ALTER TABLE employee_types DROP CONSTRAINT employee_types_system_company_check",
        []
      )

      assert_runtime_start_fails!(env, :employee)

      run_mix!(
        "bilimbi.rollback",
        ["--step", to_string(length(recovery_entries)), "--quiet"],
        env
      )

      Enum.each(recovery_versions, &refute(&1 in recorded_versions()))
      run_mix!("bilimbi.migrate", ["--quiet"], env)
      Enum.each(recovery_versions, &assert(&1 in recorded_versions()))
      run_mix!("app.start", [], env)

      assert run_mix!(
               "run",
               ["-e", "Bilimbi.Core.Compatibility.PlatformBaselineSmoke.run()"],
               env
             ) =~ "Platform baseline public API smoke passed."
    end)
  end

  test "operational commands adopt compatible structure before pending Bilimbi-only work",
       %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      latest_baseline_version = List.last(Compatibility.baseline_versions())

      run_mix!("bilimbi.migrate", ["--quiet"], env)

      run_mix!(
        "bilimbi.rollback",
        ["--to-exclusive", Integer.to_string(latest_baseline_version), "--quiet"],
        env
      )

      SQL.query!(PlatformBaselineTestRepo, "DROP TABLE bilimbi_schema_migrations", [])
      install_legacy_queue_sentinels!()
      assert_runtime_start_fails!(env, :queue)
      assert relation("oban_jobs") == nil

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert run_mix!("bilimbi.schema.adopt", [], env) =~
               "Existing Belimbing schema verified and adopted by Bilimbi."

      assert recorded_versions() == Compatibility.baseline_versions()

      assert run_mix!("bilimbi.migrations", [], env) =~ "down"
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      assert recorded_versions() == Enum.map(Compatibility.migration_entries(), &elem(&1, 0))
      assert relation("oban_jobs") == "oban_jobs"
      assert oban_migrated_version() == 14
      assert_legacy_queue_sentinels_unchanged!()
      run_mix!("app.start", [], env)
    end)
  end

  test "rollback refuses to discard active postcode override provenance", %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      SQL.query!(
        PlatformBaselineTestRepo,
        """
        INSERT INTO geonames_countries
          (iso, iso3, iso_numeric, country, population, continent)
        VALUES ('MY', 'MYS', '458', 'Malaysia', 0, 'AS')
        """,
        []
      )

      SQL.query!(
        PlatformBaselineTestRepo,
        """
        WITH materialized AS (
          INSERT INTO geonames_postcodes (country_iso, postcode, place_name)
          VALUES ('MY', '50000', 'Local correction')
          RETURNING id
        )
        INSERT INTO geonames_postcode_overrides
          (applied_postcode_id, country_iso, postcode, place_name, lock_version,
           created_at, updated_at)
        SELECT id, 'MY', '50000', 'Local correction', 1,
               timezone('UTC', now()), timezone('UTC', now())
        FROM materialized
        """,
        []
      )

      step = rollback_step_to(Bilimbi.Core.Geonames.Migrations.CreatePostcodeOverrides)
      {output, status} = run_mix("bilimbi.rollback", ["--step", to_string(step), "--quiet"], env)

      assert status != 0
      assert output =~ "cannot roll back postcode overrides while operator corrections exist"
      assert relation("geonames_postcode_overrides") == "geonames_postcode_overrides"
      assert 20_260_820_143_500 in recorded_versions()
    end)
  end

  test "rollback refuses to discard retained performance history", %{env: env} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      SQL.query!(
        PlatformBaselineTestRepo,
        """
        INSERT INTO base_perf_samples
          (kind, identity, outcome, duration_ms, db_duration_ms, db_count, observed_at)
        VALUES ('request', '/health', 'ok', 12, 0, 0, timezone('UTC', now()))
        """,
        []
      )

      step = rollback_step_to(Bilimbi.Base.Perf.Migrations.CreateSamples)
      {output, status} = run_mix("bilimbi.rollback", ["--step", to_string(step), "--quiet"], env)

      assert status != 0
      assert output =~ "cannot roll back Base Perf while performance history exists"
      assert relation("base_perf_samples") == "base_perf_samples"
      assert 20_260_821_213_000 in recorded_versions()
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

  defp assert_runtime_start_fails!(env, boundary) do
    {output, status} = run_mix("app.start", [], env)

    assert status != 0

    case boundary do
      :queue ->
        assert output =~ "Oban migrations have not been run"

      :employee ->
        assert output =~ "required runtime schema is missing: employee_types_system_company_check"
    end
  end

  defp recorded_versions do
    SQL.query!(
      PlatformBaselineTestRepo,
      "SELECT version FROM bilimbi_schema_migrations ORDER BY version",
      []
    ).rows
    |> Enum.map(fn [version] -> version end)
  end

  defp rollback_step_to(module) do
    Compatibility.migration_entries()
    |> Enum.reverse()
    |> Enum.find_index(fn {_version, migration_module, _disposition} ->
      migration_module == module
    end)
    |> case do
      nil -> raise ArgumentError, "unknown migration module: #{inspect(module)}"
      index -> index + 1
    end
  end

  defp relation(table) do
    [[relation]] =
      SQL.query!(PlatformBaselineTestRepo, "SELECT to_regclass($1)::text", [table]).rows

    relation
  end

  defp oban_migrated_version do
    Oban.Migrations.Postgres.migrated_version(repo: PlatformBaselineTestRepo)
  end

  defp install_legacy_queue_sentinels! do
    for table <- ~w(jobs job_batches failed_jobs) do
      SQL.query!(
        PlatformBaselineTestRepo,
        "CREATE TABLE #{table} (id bigint PRIMARY KEY, payload text NOT NULL)",
        []
      )

      SQL.query!(
        PlatformBaselineTestRepo,
        "INSERT INTO #{table} (id, payload) VALUES (1, $1)",
        ["legacy-#{table}-payload"]
      )
    end
  end

  defp assert_legacy_queue_sentinels_unchanged! do
    for table <- ~w(jobs job_batches failed_jobs) do
      expected_payload = "legacy-#{table}-payload"

      assert [[1, ^expected_payload]] =
               SQL.query!(
                 PlatformBaselineTestRepo,
                 "SELECT id, payload FROM #{table}",
                 []
               ).rows
    end
  end
end
