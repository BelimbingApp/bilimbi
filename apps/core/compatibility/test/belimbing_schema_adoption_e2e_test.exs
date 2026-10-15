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

    # The dump holds the Platform's tables only: a mounted Domain's baseline
    # would be reported as missing, which is the documented refusal.
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

      # The Laravel fixture contains Platform tables. Optional owners whose
      # tables are absent remain pending until migrate creates their baseline.
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

  test "person backfill preserves HR facts, user links, agent identities and sequences", %{
    env: env
  } do
    BelimbingSchemaFixture.load!(PlatformBaselineTestRepo.config())

    SQL.query!(
      PlatformBaselineTestRepo,
      "INSERT INTO tenants(id, name, is_platform_operator) VALUES (947, 'Legacy operator', true)",
      []
    )

    SQL.query!(
      PlatformBaselineTestRepo,
      "INSERT INTO companies(id, tenant_id, name, code, status) VALUES (947, 947, 'Legacy company', 'legacy_947', 'active')",
      []
    )

    SQL.query!(
      PlatformBaselineTestRepo,
      "INSERT INTO tenant_primary_companies(tenant_id, company_id) VALUES (947, 947)",
      []
    )

    SQL.query!(
      PlatformBaselineTestRepo,
      """
      INSERT INTO employees(id, company_id, employee_number, full_name, designation, email, mobile_number, employee_type, status, employment_start, employment_end, metadata)
      VALUES (9470, 947, 'HR-947', 'Legacy Human', 'Engineer', 'legacy@work.test', '+60947', 'part_time', 'probation', '2020-01-02', '2027-03-04', '{"legacy":"preserved"}')
      """,
      []
    )

    SQL.query!(
      PlatformBaselineTestRepo,
      """
      INSERT INTO employees(id, company_id, supervisor_id, employee_number, full_name, employee_type, status)
      VALUES (9471, 947, 9470, 'SYS-001', 'Legacy System Agent', 'agent', 'active')
      """,
      []
    )

    SQL.query!(
      PlatformBaselineTestRepo,
      """
      INSERT INTO users(id, company_id, employee_id, name, email, password)
      VALUES (9472, 947, 9470, 'Legacy login', 'legacy947@example.test', 'retained-hash')
      """,
      []
    )

    SQL.query!(
      PlatformBaselineTestRepo,
      """
      INSERT INTO employees(id, company_id, employee_number, full_name, employee_type, status, employment_start, employment_end, created_at, updated_at)
      VALUES
        (9473, 947, 'HR-947-CLOSED', 'Closed Before Recorded', 'full_time', 'inactive', NULL, '2020-01-01', '2024-06-01', '2024-06-01'),
        (9474, 947, 'HR-947-UNDATED', 'Undated Record', 'full_time', 'active', NULL, NULL, '2024-06-01', '2024-06-01')
      """,
      []
    )

    before =
      SQL.query!(
        PlatformBaselineTestRepo,
        "SELECT row_to_json(e) FROM employees e ORDER BY id",
        []
      ).rows

    run_mix!("bilimbi.schema.adopt", [], env)
    run_mix!("bilimbi.migrate", ["--quiet"], env)

    assert SQL.query!(
             PlatformBaselineTestRepo,
             "SELECT row_to_json(e) FROM employees e ORDER BY id",
             []
           ).rows == before

    assert [[9470]] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT employee_id FROM users WHERE id = 9472",
               []
             ).rows

    assert [
             [9470, 9470, 947, "Engineer"],
             [9471, 9471, 947, nil],
             [9473, 9473, 947, nil],
             [9474, 9474, 947, nil]
           ] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT legacy_employee_id, person_id, company_id, title FROM core_person_affiliations ORDER BY legacy_employee_id",
               []
             ).rows

    assert [
             [9470, ~D[2020-01-02], ~D[2027-03-04]],
             [9471, nil, nil],
             [9473, nil, ~D[2020-01-01]],
             [9474, nil, nil]
           ] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT legacy_employee_id, started_on, ended_on FROM core_person_affiliations ORDER BY legacy_employee_id",
               []
             ).rows

    assert [["legacy@work.test", "+60947"]] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT email, phone FROM core_person_affiliations WHERE legacy_employee_id = 9470",
               []
             ).rows

    assert [[nil, nil]] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT email, phone FROM core_people WHERE id = 9470",
               []
             ).rows

    assert [
             [9470, 947, "Legacy Human", nil],
             [9471, 947, "Legacy System Agent", nil],
             [9473, 947, "Closed Before Recorded", ~N[2024-06-01 00:00:00]],
             [9474, 947, "Undated Record", ~N[2024-06-01 00:00:00]]
           ] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT id, tenant_id, full_name, created_at FROM core_people ORDER BY id",
               []
             ).rows

    assert [[true]] =
             SQL.query!(
               PlatformBaselineTestRepo,
               "SELECT nextval('core_people_id_seq') > 9474",
               []
             ).rows

    assert run_mix!("bilimbi.schema.verify", [], env) =~ "Bilimbi compatibility schema verified."
  end
end
