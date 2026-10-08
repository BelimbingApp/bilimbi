defmodule Bilimbi.Core.PlatformBaselineE2ETest do
  # Each test runs twice: on the Platform alone, and with a throwaway Domain
  # mounted beside it. A mounted Domain's migrations join every host task, so
  # the expected migrations come from the umbrella root's runtime, as the
  # host tasks see them, never from this package's partial closure.
  use ExUnit.Case,
    async: false,
    parameterize: [%{mounted_domain: false}, %{mounted_domain: true}]

  @moduletag timeout: 180_000

  import Bilimbi.Core.Compatibility.HostTaskHarness

  alias Bilimbi.Base.Database
  alias Bilimbi.Core.Compatibility.MountedDomainFixture
  alias Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnostics
  alias Bilimbi.Core.Compatibility.PlatformBaselineTestRepo
  alias Ecto.Adapters.SQL

  setup_all %{mounted_domain: mounted_domain} do
    # Load this package's runtime smoke and schema fixtures before nested
    # commands start. Host and package commands now share the same test build.
    {:ok, modules} = :application.get_key(:bilimbi_core_compatibility, :modules)
    Enum.each(modules, &Code.ensure_loaded!/1)

    # A pinned composition lock names the mounted repositories, and the
    # fixture is not one of them.
    env = if mounted_domain, do: [{"BILIMBI_COMPOSITION_PINNED", nil}], else: []

    MountedDomainFixture.unmount!()
    if mounted_domain, do: MountedDomainFixture.mount!()

    entries = workspace_migration_entries(env)

    for {version, disposition} <- [
          {MountedDomainFixture.baseline_version(), :compatible_baseline},
          {MountedDomainFixture.version(), :bilimbi_only}
        ] do
      assert Enum.any?(entries, &match?({^version, _, ^disposition}, &1)) == mounted_domain
    end

    %{base_env: env, migration_entries: entries}
  end

  setup context, do: setup_databases(context)

  test "the operational fresh install verifies and supports the public identity APIs",
       %{env: env, migration_entries: entries} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      assert_runtime_start_fails!(env, :queue)
      assert run_mix!("bilimbi.migrations", [], env) =~ "down"

      run_mix!("bilimbi.migrate", ["--quiet"], env)
      run_mix!("app.start", [], env)

      assert relation("oban_jobs") == "oban_jobs"
      assert oban_migrated_version() == 14

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert recorded_versions() == Enum.map(entries, &elem(&1, 0))

      if context.mounted_domain do
        assert relation(MountedDomainFixture.table()) == MountedDomainFixture.table()
      end

      recovery_entries =
        entries
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
       %{env: env, migration_entries: entries} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      baseline_versions = for {version, _module, :compatible_baseline} <- entries, do: version

      # An existing Belimbing database holds every installed baseline and no
      # Bilimbi-only work. A mounted Domain's baseline can follow Platform
      # Bilimbi-only migrations, so no single rollback reaches that state.
      migrate_baselines_only!(env)
      SQL.query!(PlatformBaselineTestRepo, "DROP TABLE bilimbi_schema_migrations", [])
      SQL.query!(PlatformBaselineTestRepo, "DROP TABLE bilimbi_migration_provenance", [])
      install_legacy_queue_sentinels!()
      assert_runtime_start_fails!(env, :queue)
      assert relation("oban_jobs") == nil

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert run_mix!("bilimbi.schema.adopt", [], env) =~
               "Existing Belimbing schema verified and adopted by Bilimbi."

      assert recorded_versions() == baseline_versions

      if context.mounted_domain do
        assert relation(MountedDomainFixture.baseline_table()) ==
                 MountedDomainFixture.baseline_table()

        assert relation(MountedDomainFixture.table()) == nil
      end

      assert run_mix!("bilimbi.migrations", [], env) =~ "down"
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      assert recorded_versions() == Enum.map(entries, &elem(&1, 0))
      assert relation("oban_jobs") == "oban_jobs"
      assert oban_migrated_version() == 14
      assert_legacy_queue_sentinels_unchanged!()
      run_mix!("app.start", [], env)
    end)
  end

  test "operational commands leave an absent Domain's baseline for migrate to create",
       %{env: env, migration_entries: entries} = context do
    if context.mounted_domain do
      PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
        baseline_versions = for {version, _module, :compatible_baseline} <- entries, do: version
        domain_baseline = MountedDomainFixture.baseline_version()
        baseline_table = MountedDomainFixture.baseline_table()

        # An existing Belimbing database whose installation never had the
        # Belimbing module the Domain maps: every Platform baseline's
        # structure, none of the Domain's, and no Bilimbi ledger.
        migrate_baselines_only!(env)
        SQL.query!(PlatformBaselineTestRepo, "DROP TABLE bilimbi_schema_migrations", [])
        SQL.query!(PlatformBaselineTestRepo, "DROP TABLE bilimbi_migration_provenance", [])
        SQL.query!(PlatformBaselineTestRepo, "DROP TABLE #{baseline_table}", [])

        note = "e2e_fixture/ledger: no owned structure exists in this database"
        verified = run_mix!("bilimbi.schema.verify", [], env)
        assert verified =~ "Bilimbi compatibility schema verified."
        assert verified =~ note

        adopted = run_mix!("bilimbi.schema.adopt", [], env)
        assert adopted =~ "Existing Belimbing schema verified and adopted by Bilimbi."
        assert adopted =~ note
        assert recorded_versions() == baseline_versions -- [domain_baseline]
        assert relation(baseline_table) == nil

        run_mix!("bilimbi.migrate", ["--quiet"], env)
        assert recorded_versions() == Enum.map(entries, &elem(&1, 0))
        assert relation(baseline_table) == baseline_table
        assert relation(MountedDomainFixture.table()) == MountedDomainFixture.table()
        refute run_mix!("bilimbi.schema.verify", [], env) =~ note
      end)
    end
  end

  test "rollback refuses to discard active postcode override provenance",
       %{env: env, migration_entries: entries} = context do
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

      step = rollback_step_to(entries, Bilimbi.Core.Geonames.Migrations.CreatePostcodeOverrides)
      {output, status} = run_mix("bilimbi.rollback", ["--step", to_string(step), "--quiet"], env)

      assert status != 0
      assert output =~ "cannot roll back postcode overrides while operator corrections exist"
      assert relation("geonames_postcode_overrides") == "geonames_postcode_overrides"
      assert 20_260_820_143_500 in recorded_versions()
    end)
  end

  test "rollback refuses to discard retained performance history",
       %{env: env, migration_entries: entries} = context do
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

      step = rollback_step_to(entries, Bilimbi.Base.Perf.Migrations.CreateSamples)
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
end
