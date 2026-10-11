defmodule Bilimbi.Core.BelimbingSchemaAdoptionE2ETest do
  # The adoption path against a database Laravel really created, not one
  # built from Bilimbi's own baselines. A baseline that only ever met itself
  # cannot show a constraint Laravel made differently, an index Belimbing
  # already has, or a column upstream added after the baseline was written.
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  import Bilimbi.Core.Compatibility.HostTaskHarness

  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.BelimbingSchemaFixture
  alias Bilimbi.Core.Compatibility.MountedDomainFixture
  alias Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnostics
  alias Bilimbi.Core.Compatibility.PlatformBaselineTestRepo
  alias Ecto.Adapters.SQL

  @laravel_sentinel "0000_00_00_000000_fixture_sentinel"

  setup_all do
    {:ok, modules} = :application.get_key(:bilimbi_core_compatibility, :modules)
    Enum.each(modules, &Code.ensure_loaded!/1)

    # The dump holds Platform tables only. Remove the throwaway fixture from
    # prior runs; real optional Domains may remain installed, and adoption
    # leaves their baselines pending when their structure is absent.
    MountedDomainFixture.unmount!()

    %{
      base_env: [],
      migration_entries: workspace_migration_entries([]),
      platform_entries: workspace_migration_entries([], [:base, :core])
    }
  end

  setup context, do: setup_databases(context)

  test "the fixture is dumped from the pinned compatibility source" do
    assert BelimbingSchemaFixture.source_commit() == Compatibility.compatibility_source()
  end

  test "verify, adopt and migrate a database Belimbing's own migrations created",
       %{env: env, migration_entries: entries, platform_entries: platform_entries} = context do
    PlatformBaselineFailureDiagnostics.capture(context, :test, fn ->
      BelimbingSchemaFixture.load!(PlatformBaselineTestRepo.config())

      # Laravel's ledger is Laravel's. The dump leaves it empty; one row shows
      # it is never read, written or renamed.
      SQL.query!(
        PlatformBaselineTestRepo,
        "INSERT INTO migrations (migration, batch) VALUES ($1, 1)",
        [@laravel_sentinel]
      )

      assert relation("bilimbi_schema_migrations") == nil
      assert relation("oban_jobs") == nil
      assert_runtime_start_fails!(env, :queue)

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert run_mix!("bilimbi.schema.adopt", [], env) =~
               "Existing Belimbing schema verified and adopted by Bilimbi."

      # This fixture contains Platform tables only. An installed optional
      # Domain absent from it correctly leaves its baseline pending at adoption.
      baseline_versions =
        for {version, _module, :compatible_baseline} <- platform_entries, do: version

      assert recorded_versions() == baseline_versions

      assert run_mix!("bilimbi.migrations", [], env) =~ "down"
      run_mix!("bilimbi.migrate", ["--quiet"], env)

      assert recorded_versions() == Enum.map(entries, &elem(&1, 0))
      assert relation("oban_jobs") == "oban_jobs"

      assert run_mix!("bilimbi.schema.verify", [], env) =~
               "Bilimbi compatibility schema verified."

      assert [[@laravel_sentinel]] =
               SQL.query!(PlatformBaselineTestRepo, "SELECT migration FROM migrations", []).rows

      run_mix!("app.start", [], env)

      assert run_mix!(
               "run",
               ["-e", "Bilimbi.Core.Compatibility.PlatformBaselineSmoke.run()"],
               env
             ) =~ "Platform baseline public API smoke passed."
    end)
  end
end
