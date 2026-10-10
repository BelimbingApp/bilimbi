Code.require_file(
  Path.expand("../../../base/workflow/test/support/legacy_coordination_fixture.ex", __DIR__)
)

Code.require_file(
  Path.expand("../../../base/workflow/test/support/legacy_status_fixture.ex", __DIR__)
)

Code.require_file(
  Path.expand("../../../base/workflow/test/support/legacy_human_action_fixture.ex", __DIR__)
)

defmodule Bilimbi.Core.CompatibilityTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Ecto.Adapters.SQL

  setup do
    repo_options =
      Bilimbi.Base.Repo.config()
      |> Keyword.put(:name, MigrationTestRepo)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)

    Application.put_env(:bilimbi_base_database, MigrationTestRepo, repo_options)

    on_exit(fn ->
      Application.delete_env(:bilimbi_base_database, MigrationTestRepo)
    end)

    start_supervised!(MigrationTestRepo)

    schema =
      "bilimbi_baseline_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    SQL.query!(MigrationTestRepo, ~s(CREATE SCHEMA "#{schema}"), [])

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Bilimbi.Base.Repo, fn ->
        SQL.query!(
          Bilimbi.Base.Repo,
          ~s(DROP SCHEMA IF EXISTS "#{schema}" CASCADE),
          []
        )
      end)
    end)

    %{schema: schema}
  end

  test "fresh migration creates the complete compatible baseline with an independent ledger", %{
    schema: schema
  } do
    all_versions = Enum.map(Compatibility.migration_entries(), &elem(&1, 0))
    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == all_versions

    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert [[0]] =
             SQL.query!(
               MigrationTestRepo,
               "SELECT count(*) FROM \"#{schema}\".tenants",
               []
             ).rows

    assert [[0]] =
             SQL.query!(
               MigrationTestRepo,
               "SELECT count(*) FROM \"#{schema}\".sessions",
               []
             ).rows

    for table <- ~w(geonames_countries geonames_admin1 geonames_postcodes geonames_cities) do
      assert [[0]] =
               SQL.query!(
                 MigrationTestRepo,
                 "SELECT count(*) FROM \"#{schema}\".\"#{table}\"",
                 []
               ).rows
    end

    for table <- ~w(
          base_authz_roles
          base_authz_role_capabilities
          base_authz_principal_roles
          base_authz_principal_capabilities
          base_authz_decision_logs
        ) do
      assert [[0]] =
               SQL.query!(
                 MigrationTestRepo,
                 "SELECT count(*) FROM \"#{schema}\".\"#{table}\"",
                 []
               ).rows
    end

    SQL.query!(
      MigrationTestRepo,
      "SELECT setval(to_regclass($1), 40, true)",
      ["#{schema}.tenants_id_seq"]
    )

    assert [[41]] =
             SQL.query!(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".tenants (
                 name, status, is_platform_operator
               )
               VALUES ('Platform operator', 'active', true)
               RETURNING id
               """,
               []
             ).rows

    assert [[42]] =
             SQL.query!(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".tenants (name, status)
               VALUES ('Customer', 'active')
               RETURNING id
               """,
               []
             ).rows

    SQL.query!(
      MigrationTestRepo,
      "SELECT setval(to_regclass($1), 72, true)",
      ["#{schema}.companies_id_seq"]
    )

    assert [[73, 41]] =
             SQL.query!(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".companies (tenant_id, name, code)
               VALUES (41, 'Operator', 'operator')
               RETURNING id, tenant_id
               """,
               []
             ).rows

    assert {:error, %Postgrex.Error{}} =
             SQL.query(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".tenant_primary_companies (tenant_id, company_id)
               VALUES (42, 73)
               """,
               []
             )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".geonames_countries (
        iso, iso3, iso_numeric, country, population, continent
      )
      VALUES ('MY', 'MYS', '458', 'Malaysia', 0, 'AS')
      """,
      []
    )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".geonames_admin1 (code, name)
      VALUES ('MY.14', 'Kuala Lumpur')
      """,
      []
    )

    assert %Postgrex.Result{num_rows: 1} =
             SQL.query!(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".tenant_primary_companies (tenant_id, company_id)
               VALUES (41, 73)
               """,
               []
             )

    assert {:error, %Postgrex.Error{}} =
             SQL.query(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".companies (parent_id, tenant_id, name, code)
               VALUES (73, 42, 'Cross-tenant child', 'cross_tenant_child')
               """,
               []
             )

    assert {:error, %Postgrex.Error{}} =
             SQL.query(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".companies (name, code)
               VALUES ('No owner', 'no_owner')
               """,
               []
             )

    assert {:error, %Postgrex.Error{}} =
             SQL.query(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".tenants (name, status, is_platform_operator)
               VALUES ('Second operator', 'active', true)
               """,
               []
             )

    assert [] == timestamp_columns(MigrationTestRepo, schema, "tenant_primary_companies")

    assert {:error, %Postgrex.Error{}} =
             SQL.query(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".addresses (label)
               VALUES ('Missing tenant')
               """,
               []
             )

    assert [[address_id, 41, "MY", "MY.14", "unverified"]] =
             SQL.query!(
               MigrationTestRepo,
               """
                INSERT INTO "#{schema}".addresses (
                 tenant_id, label, country_iso, "admin1Code", normalization_notes
                )
               VALUES (41, 'Operator HQ', 'MY', 'MY.14', '["verified source"]'::json)
               RETURNING id, tenant_id, country_iso, "admin1Code", "verificationStatus"
               """,
               []
             ).rows

    assert is_integer(address_id)

    assert [["[]", false, 0]] =
             SQL.query!(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".addressables (
                 address_id, addressable_type, addressable_id
               )
               VALUES ($1, 'App\\Core\\Company\\Models\\Company', 73)
               RETURNING kind::text, is_primary, priority
               """,
               [address_id]
             ).rows

    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") != nil
    assert relation(MigrationTestRepo, schema, "migrations") == nil

    assert recorded_versions(MigrationTestRepo, schema) ==
             Enum.map(Compatibility.migration_entries(), &elem(&1, 0))
  end

  test "fresh migration executes compatible and Bilimbi-only contributions", %{schema: schema} do
    synthetic_version = install_synthetic_migration!()

    expected_versions = Enum.map(Compatibility.migration_entries(), &elem(&1, 0))

    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) ==
             expected_versions

    assert relation(MigrationTestRepo, schema, "bilimbi_only_probe") != nil
    assert relation(MigrationTestRepo, schema, "users_company_id_index") != nil
    assert relation(MigrationTestRepo, schema, "users_employee_id_index") != nil
    assert recorded_versions(MigrationTestRepo, schema) == expected_versions
    refute synthetic_version in Compatibility.baseline_versions()
  end

  test "adoption verifies a compatible Belimbing schema before recording baselines", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    assert {:ok, :adopted} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert recorded_versions(MigrationTestRepo, schema) ==
             Compatibility.baseline_versions()

    assert {:ok, :already_adopted} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)
  end

  test "pending migrations follow the ledger from missing through baseline to complete", %{
    schema: schema
  } do
    entries = Compatibility.migration_entries()
    all_versions = Enum.map(entries, &elem(&1, 0))

    pending_versions = fn ->
      Enum.map(Compatibility.pending_migrations(MigrationTestRepo, prefix: schema), & &1.version)
    end

    # No ledger yet: everything installed is pending, each with its owner.
    pending = Compatibility.pending_migrations(MigrationTestRepo, prefix: schema)
    assert Enum.map(pending, & &1.version) == all_versions
    assert Enum.all?(pending, &(&1.owner_id =~ ~r{^(base|core|domain|extension)/}))

    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)

    assert pending_versions.() ==
             for({version, _module, :bilimbi_only} <- entries, do: version)

    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    assert pending_versions.() == []
  end

  test "migration is refused on an unadopted Belimbing database until it is adopted", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    # A fresh database has neither Laravel's migrations table nor a ledger.
    refute Compatibility.unadopted_belimbing?(MigrationTestRepo, prefix: schema)
    assert :ok = Compatibility.ensure_adopted!(MigrationTestRepo, prefix: schema)

    SQL.query!(
      MigrationTestRepo,
      ~s|CREATE TABLE "#{schema}".migrations (id serial PRIMARY KEY, migration varchar NOT NULL, batch integer NOT NULL)|,
      []
    )

    assert Compatibility.unadopted_belimbing?(MigrationTestRepo, prefix: schema)

    assert_raise ArgumentError, ~r/not adopted.*verify, adopt, remap/s, fn ->
      Compatibility.ensure_adopted!(MigrationTestRepo, prefix: schema)
    end

    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
    refute Compatibility.unadopted_belimbing?(MigrationTestRepo, prefix: schema)
    assert :ok = Compatibility.ensure_adopted!(MigrationTestRepo, prefix: schema)
  end

  test "adoption advances a verified prefix from an earlier Bilimbi baseline", %{schema: schema} do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    previous_versions = Enum.take(Compatibility.baseline_versions(), 3)

    SQL.query!(
      MigrationTestRepo,
      "DELETE FROM \"#{schema}\".bilimbi_schema_migrations WHERE version > $1",
      [List.last(previous_versions)]
    )

    assert recorded_versions(MigrationTestRepo, schema) == previous_versions

    assert {:ok, :advanced} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert recorded_versions(MigrationTestRepo, schema) ==
             Compatibility.baseline_versions()
  end

  test "adoption leaves an interleaved Bilimbi-only migration pending for normal migration", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)
    synthetic_version = install_synthetic_migration!()

    assert relation(MigrationTestRepo, schema, "bilimbi_only_probe") == nil
    assert relation(MigrationTestRepo, schema, "users_company_id_index") == nil
    assert relation(MigrationTestRepo, schema, "users_employee_id_index") == nil

    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert recorded_versions(MigrationTestRepo, schema) == Compatibility.baseline_versions()
    refute synthetic_version in recorded_versions(MigrationTestRepo, schema)

    pending =
      Compatibility.migration_entries()
      |> Enum.filter(&(elem(&1, 2) == :bilimbi_only))
      |> Enum.map(&elem(&1, 0))

    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == pending

    assert relation(MigrationTestRepo, schema, "bilimbi_only_probe") != nil
    assert relation(MigrationTestRepo, schema, "users_company_id_index") != nil
    assert relation(MigrationTestRepo, schema, "users_employee_id_index") != nil

    assert recorded_versions(MigrationTestRepo, schema) ==
             Enum.map(Compatibility.migration_entries(), &elem(&1, 0))

    assert {:ok, :already_adopted} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)
  end

  test "migrate accepts the account indexes a Belimbing database already has", %{schema: schema} do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    for column <- ~w(company_id employee_id) do
      SQL.query!(
        MigrationTestRepo,
        "CREATE INDEX users_#{column}_index ON \"#{schema}\".users (#{column})",
        []
      )
    end

    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) != []
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert recorded_versions(MigrationTestRepo, schema) ==
             Enum.map(Compatibility.migration_entries(), &elem(&1, 0))
  end

  test "a database migrated before the tenant and provenance columns still migrates", %{
    schema: schema
  } do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    account_indexes = 20_260_821_213_100
    decision_log_tenant = 20_261_008_070_000
    run_provenance = 20_261_008_070_100
    log_backfill = 20_261_008_070_200

    assert %{disposition: "bilimbi_only"} =
             Compatibility.MigrationProvenance.fetch(MigrationTestRepo, schema)[account_indexes]

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".base_authz_decision_logs DROP COLUMN tenant_id),
      []
    )

    SQL.query!(
      MigrationTestRepo,
      """
      ALTER TABLE "#{schema}".base_schedule_runs
      DROP COLUMN trigger, DROP COLUMN triggered_by_name, DROP COLUMN triggered_by_user_id
      """,
      []
    )

    for version <- [decision_log_tenant, run_provenance, log_backfill] do
      SQL.query!(
        MigrationTestRepo,
        ~s(DELETE FROM "#{schema}".bilimbi_schema_migrations WHERE version = $1),
        [version]
      )

      SQL.query!(
        MigrationTestRepo,
        ~s(DELETE FROM "#{schema}".bilimbi_migration_provenance WHERE version = $1),
        [version]
      )
    end

    [[tenant_id]] =
      SQL.query!(
        MigrationTestRepo,
        "INSERT INTO \"#{schema}\".tenants (name) VALUES ('Acme') RETURNING id",
        []
      ).rows

    [[company_id]] =
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".companies (name, code, tenant_id)
        VALUES ('Acme Ltd', 'ACME', $1) RETURNING id
        """,
        [tenant_id]
      ).rows

    for log_company_id <- [company_id, nil] do
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".base_authz_decision_logs
          (company_id, actor_type, actor_id, capability, allowed, reason_code, occurred_at)
        VALUES ($1, 'user', 1, 'core.users.view', true, 'granted', now())
        """,
        [log_company_id]
      )
    end

    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) ==
             [decision_log_tenant, run_provenance, log_backfill]

    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert [[^tenant_id, ^company_id], [nil, nil]] =
             SQL.query!(
               MigrationTestRepo,
               """
               SELECT tenant_id, company_id FROM "#{schema}".base_authz_decision_logs ORDER BY id
               """,
               []
             ).rows
  end

  test "adoption rejects a gap inside one owner's baselines and unknown ledger versions", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)

    # Core Company ships two baselines; a ledger holding only its second is
    # not a prefix of that owner's sequence.
    [first_version | _rest] =
      for {version, module, :compatible_baseline} <- Compatibility.migration_entries(),
          String.starts_with?(inspect(module), "Bilimbi.Core.Company."),
          do: version

    SQL.query!(
      MigrationTestRepo,
      ~s(DELETE FROM "#{schema}".bilimbi_schema_migrations WHERE version = $1),
      [first_version]
    )

    non_prefix = recorded_versions(MigrationTestRepo, schema)

    assert {:error, {:ledger_conflict, ^non_prefix}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".bilimbi_schema_migrations (version, inserted_at)
      VALUES ($1, now())
      """,
      [99_999_999_999_999]
    )

    with_unknown = recorded_versions(MigrationTestRepo, schema)

    assert {:error, {:ledger_conflict, ^with_unknown}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)
  end

  test "adoption refuses schema drift and leaves no Bilimbi ledger", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".companies DROP COLUMN legal_name),
      []
    )

    assert {:error, {:schema_drift, errors}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert "companies: missing column legal_name" in errors
    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") == nil
  end

  test "a Platform module whose tables are all absent is drift", %{schema: schema} do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    # Only a Domain or Extension may be absent from a Belimbing database: the
    # Platform maps Belimbing's own tables, so a Platform module with none is
    # a database behind the compatibility source, never one to create.
    SQL.query!(MigrationTestRepo, ~s(DROP TABLE "#{schema}".sessions), [])

    assert {:error, errors} = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert "missing table #{schema}.sessions" in errors
    assert Compatibility.absent_modules(MigrationTestRepo, prefix: schema) == []

    assert {:error, {:schema_drift, _errors}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") == nil
  end

  test "verification refuses a partial cross-module contribution", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    # Core User installs this optional group whole -- column, index, and
    # foreign key. Break it by removing one member rather than by adding the
    # column, which now already exists.
    SQL.query!(
      MigrationTestRepo,
      """
      ALTER TABLE "#{schema}".company_external_accesses
      DROP CONSTRAINT company_external_accesses_user_id_foreign
      """,
      []
    )

    assert {:error, errors} = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert "company_external_accesses: incomplete optional contribution core/user external-access owner" in errors
  end

  test "the migration graph includes every installed contributor", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    # Regression guard for the defect this test was added with: a module whose
    # OTP application is not in Compatibility's dependency closure is invisible
    # to Application.loaded_applications/0, so its migrations silently never
    # run and its schema contract is never verified. Core User shipped that way.
    assert relation(MigrationTestRepo, schema, "users") != nil
    assert relation(MigrationTestRepo, schema, "notifications") != nil
    assert relation(MigrationTestRepo, schema, "base_settings") != nil

    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
  end

  test "verification requires Address's Geonames foreign keys", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      """
      ALTER TABLE "#{schema}".addresses
      DROP CONSTRAINT addresses_admin1code_foreign
      """,
      []
    )

    assert {:error, errors} = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert "addresses: missing foreign key addresses_admin1code_foreign" in errors
  end

  test "verification refuses the historical implicit tenant default", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".companies ALTER COLUMN tenant_id SET DEFAULT 1),
      []
    )

    assert {:error, errors} = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert "companies.tenant_id: incompatible default \"1\"" in errors
  end

  test "verification rejects a soft-deleted marked platform operator", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".tenants (
        name, status, is_platform_operator, deleted_at
      )
      VALUES ('Deleted operator', 'active', true, '2026-08-11 12:00:00')
      """,
      []
    )

    assert {:error, errors} = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert Enum.any?(errors, &String.contains?(&1, "platform-operator tenant"))
  end

  test "adoption and migration preserves global custom employee types from Belimbing", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    # Insert a canonical Belimbing custom employee type into the baseline schema
    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".employee_types (code, label, is_system, company_id)
      VALUES ('contractor_global', 'Contractor Global', false, NULL)
      """,
      []
    )

    # Adopt baseline
    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)

    # Run pending Bilimbi-only migrations
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    # Verify structural integrity against contracts
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)

    # Assert global custom type exists and is protected by global unique index
    assert_raise Postgrex.Error, ~r/employee_types_global_code_unique/, fn ->
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".employee_types (code, label, is_system, company_id)
        VALUES ('contractor_global', 'Duplicate Global', false, NULL)
        """,
        []
      )
    end

    # Assert system type cannot belong to a company
    assert_raise Postgrex.Error, ~r/employee_types_system_company_check/, fn ->
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".employee_types (code, label, is_system, company_id)
        VALUES ('invalid_sys', 'Invalid System', true, 81)
        """,
        []
      )
    end

    # Assert company custom types can be created with distinct or matching codes
    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".employee_types (code, label, is_system, company_id)
      VALUES ('contractor_global', 'Company 81 Custom', false, 81)
      """,
      []
    )
  end

  test "adoption preserves independently created Workflow configuration, history and sequences",
       %{schema: schema} do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)

    tables =
      ~w(base_workflow base_workflow_status_configs base_workflow_status_transitions base_workflow_status_history base_workflow_kanban_columns)

    for table <- tables,
        do: SQL.query!(MigrationTestRepo, ~s(DROP TABLE "#{schema}"."#{table}"), [])

    Bilimbi.Base.Workflow.LegacyStatusFixture.create!(MigrationTestRepo, schema)

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow (code, label, model_class, settings)
      VALUES ('example_flow', 'Example flow', $1, '{"legacy": [1, true]}')
      """,
      ["Legacy\\Example\\Record"]
    )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_status_configs (flow, code, label, pic, is_active)
      VALUES ('example_flow', 'old_state', 'Historical state', '[1, {"kind":"role"}]', false)
      """,
      []
    )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_status_transitions (flow, from_code, to_code, guard_class, action_class, metadata, is_active)
      VALUES ('example_flow', 'old_state', 'draft', $1, $2, '[{"legacy":true}]', false)
      """,
      ["Legacy\\Example\\Guard", "Legacy\\Example\\Action"]
    )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_kanban_columns (flow, code, label, settings)
      VALUES ('example_flow', 'archive', 'Archive', '["preserved"]')
      """,
      []
    )

    for {type, actor, status} <- [
          {nil, 7, "old_state"},
          {"agent", 7, "draft"},
          {"guest", nil, "draft"}
        ] do
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".base_workflow_status_history
          (flow, flow_id, status, actor_type, actor_id, assignees, attachments, metadata, transitioned_at)
        VALUES ('example_flow', 41, $1, $2, $3, '[{"kind":"role"}]', '["file"]', '[1,{"legacy":true}]', '2026-01-01 00:00:00')
        """,
        [status, type, actor]
      )
    end

    before = workflow_snapshot(MigrationTestRepo, schema, tables)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
    assert workflow_snapshot(MigrationTestRepo, schema, tables) == before
    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) != []
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert workflow_snapshot(MigrationTestRepo, schema, tables) == before

    assert [[0]] =
             SQL.query!(
               MigrationTestRepo,
               ~s|SELECT count(*) FROM "#{schema}".base_workflow_subject_bindings|,
               []
             ).rows

    assert [[4]] =
             SQL.query!(
               MigrationTestRepo,
               """
               INSERT INTO "#{schema}".base_workflow_status_history (flow, flow_id, status, transitioned_at)
               VALUES ('example_flow', 41, 'draft', '2026-01-01 00:00:01') RETURNING id
               """,
               []
             ).rows
  end

  test "Workflow verify then adopt preserves retained rows when advancing an existing ledger prefix",
       %{schema: schema} do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)

    tables =
      ~w(base_workflow base_workflow_status_configs base_workflow_status_transitions base_workflow_status_history base_workflow_kanban_columns base_workflow_human_action_requests base_workflow_process_events base_workflow_process_dependencies base_workflow_process_work_items base_workflow_process_runs base_workflow_process_definition_versions base_workflow_transition_outbox)

    for table <- tables,
        do: SQL.query!(MigrationTestRepo, ~s(DROP TABLE "#{schema}"."#{table}"), [])

    Bilimbi.Base.Workflow.LegacyStatusFixture.create!(MigrationTestRepo, schema)
    Bilimbi.Base.Workflow.LegacyCoordinationFixture.create!(MigrationTestRepo, schema)
    Bilimbi.Base.Workflow.LegacyHumanActionFixture.create!(MigrationTestRepo, schema)

    SQL.query!(
      MigrationTestRepo,
      "INSERT INTO \"#{schema}\".base_workflow (code, label, model_class) VALUES ('reference_flow', 'Reference review', 'Legacy\\\\Reference\\\\Record')",
      []
    )

    SQL.query!(
      MigrationTestRepo,
      "INSERT INTO \"#{schema}\".base_workflow_status_history (flow, flow_id, status, transitioned_at) VALUES ('reference_flow', 41, 'review', '2026-01-01')",
      []
    )

    SQL.query!(
      MigrationTestRepo,
      "INSERT INTO \"#{schema}\".base_workflow_human_action_requests (tenant_id, idempotency_key, intent_hash, action_key, subject_type, subject_id, actor_type, actor_id, result, completed_at) VALUES (1, 'retained', $1, 'reference.complete', 'Legacy\\\\Reference\\\\Record', '41', 'user', 7, '{\"saved\":true}', '2026-01-01')",
      [String.duplicate("a", 64)]
    )

    SQL.query!(
      MigrationTestRepo,
      "INSERT INTO \"#{schema}\".base_workflow_process_runs (definition_key, definition_version, definition_fingerprint, status, started_at, available_at, scope_type, tenant_id, input) VALUES ('reference.review', 1, $1, 'running', '2026-01-01', '2026-01-01', 'tenant', 1, '{\"carried\":true}')",
      [String.duplicate("b", 64)]
    )

    before = workflow_snapshot(MigrationTestRepo, schema, tables)
    previous = Enum.take(Compatibility.baseline_versions(), 2)

    SQL.query!(
      MigrationTestRepo,
      "DELETE FROM \"#{schema}\".bilimbi_schema_migrations WHERE version > $1",
      [List.last(previous)]
    )

    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert {:ok, :advanced} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
    assert workflow_snapshot(MigrationTestRepo, schema, tables) == before
    assert recorded_versions(MigrationTestRepo, schema) == Compatibility.baseline_versions()
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
  end

  test "verify then adopt preserves legacy coordination rows, in-flight work, states and sequences",
       %{schema: schema} do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)

    tables =
      ~w(base_workflow_human_action_requests base_workflow_process_events base_workflow_process_dependencies base_workflow_process_work_items base_workflow_process_runs base_workflow_process_definition_versions base_workflow_transition_outbox)

    for table <- tables,
        do: SQL.query!(MigrationTestRepo, ~s(DROP TABLE "#{schema}"."#{table}"), [])

    fixture = Bilimbi.Base.Workflow.LegacyCoordinationFixture
    fixture.create!(MigrationTestRepo, schema)
    Bilimbi.Base.Workflow.LegacyHumanActionFixture.create!(MigrationTestRepo, schema)
    saved = fixture.insert_in_flight!(MigrationTestRepo, schema)

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_process_dependencies
        (work_item_id, depends_on_work_item_id, acceptable_outcomes, tenant_id)
      VALUES ($1, $2, '["completed", "waived"]', 1)
      """,
      [saved.items["third"], saved.items["first"]]
    )

    for status <- ~w(paused completed failed blocked) do
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".base_workflow_process_runs
          (definition_key, definition_version, definition_fingerprint, status,
           started_at, available_at, scope_type, tenant_id, pause_reason, input, output)
        VALUES ('example.retired', 3, $1, $2, '2026-01-01', '2026-01-01', 'tenant', 1,
          'Retained reason', '[1,{"carried":true}]', '{"saved":true}')
        """,
        [String.duplicate("a", 64), status]
      )
    end

    [[unresolved]] =
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".base_workflow_process_runs
          (definition_key, definition_version, definition_fingerprint, status, started_at, available_at)
        VALUES ('example.retired', 3, $1, 'running', '2026-01-01', '2026-01-01') RETURNING id
        """,
        [String.duplicate("b", 64)]
      ).rows

    for {status, index} <-
          Enum.with_index(~w(pending available leased completed failed waived blocked)) do
      SQL.query!(
        MigrationTestRepo,
        """
        INSERT INTO "#{schema}".base_workflow_process_work_items
          (process_run_id, step_key, label, executor_key, status, version, attempts,
           lease_token, lease_expires_at, input, output, outcome)
        VALUES ($1, $2, 'Retained work', 'example.retired', $3, 5, 1,
          $4, '2026-01-02', '[1,{"saved":true}]', '{"fact":42}', $3)
        """,
        [unresolved, "retained-#{index}", status, "retained-lease-#{index}"]
      )
    end

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_transition_outbox
        (event_key, event_type, payload, attempts, available_at, lease_token, lease_expires_at, last_error)
      VALUES ('retained-dispatch', 'example.changed', '[1,{"saved":true}]', 2,
        '2026-01-01', 'retained-outbox-lease', '2026-01-02', 'Retry delivery')
      """,
      []
    )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_human_action_requests
        (tenant_id, idempotency_key, intent_hash, action_key, subject_type, subject_id,
         process_run_id, work_item_id, actor_type, actor_id, result, completed_at)
      VALUES (1, 'retained-request', $1, 'example.approve', 'Legacy\\Example\\Record', '41',
        $2, $3, 'human_user', 7, '{"saved":true}', '2026-01-01')
      """,
      [String.duplicate("c", 64), saved.run_id, saved.items["second"]]
    )

    before = workflow_snapshot(MigrationTestRepo, schema, tables)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
    assert workflow_snapshot(MigrationTestRepo, schema, tables) == before
    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) != []
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert workflow_snapshot(MigrationTestRepo, schema, tables) == before

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".base_workflow_process_work_items ALTER COLUMN input TYPE jsonb USING input::jsonb),
      []
    )

    assert {:error, drift} = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert Enum.any?(drift, &String.contains?(&1, "base_workflow_process_work_items.input"))
  end

  test "Workflow adoption refuses JSON drift and a sequence behind retained history", %{
    schema: schema
  } do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".base_workflow ALTER COLUMN settings TYPE jsonb USING settings::jsonb),
      []
    )

    assert {:error, {:schema_drift, errors}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert Enum.any?(errors, &String.contains?(&1, "settings"))
    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") == nil

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".base_workflow ALTER COLUMN settings TYPE json USING settings::json),
      []
    )

    SQL.query!(
      MigrationTestRepo,
      """
      INSERT INTO "#{schema}".base_workflow_status_history (id, flow, flow_id, status, transitioned_at)
      VALUES (90, 'example_flow', 41, 'draft', '2026-01-01 00:00:00')
      """,
      []
    )

    assert {:error, {:schema_drift, errors}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert Enum.any?(errors, &String.contains?(&1, "sequence would reuse"))
    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") == nil
  end

  defp workflow_snapshot(repo, schema, tables) do
    Map.new(tables, fn table ->
      rows =
        SQL.query!(
          repo,
          ~s|SELECT row_to_json(t)::text FROM "#{schema}"."#{table}" t ORDER BY id|,
          []
        ).rows

      sequence =
        SQL.query!(repo, ~s(SELECT last_value, is_called FROM "#{schema}"."#{table}_id_seq"), []).rows

      {table, {rows, sequence}}
    end)
  end

  defp drop_bilimbi_ledger!(repo, schema) do
    SQL.query!(repo, ~s(DROP TABLE "#{schema}".bilimbi_schema_migrations), [])
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
      Path.join(path, "20260812000000_create_bilimbi_only_probe.exs"),
      """
      defmodule Bilimbi.Core.Compatibility.TestMigrations.CreateBilimbiOnlyProbe#{suffix} do
        use Ecto.Migration

        def change do
          create table(:bilimbi_only_probe, primary_key: false) do
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
      ~s(SELECT version FROM "#{schema}".bilimbi_schema_migrations ORDER BY version),
      []
    ).rows
    |> Enum.map(fn [version] -> version end)
  end

  defp timestamp_columns(repo, schema, table) do
    SQL.query!(
      repo,
      """
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = $1
        AND table_name = $2
        AND column_name IN ('created_at', 'updated_at')
      ORDER BY column_name
      """,
      [schema, table]
    ).rows
  end
end
