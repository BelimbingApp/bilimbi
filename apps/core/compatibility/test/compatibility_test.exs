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
    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) ==
             Compatibility.baseline_versions()

    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)

    assert [[0]] =
             SQL.query!(
               MigrationTestRepo,
               "SELECT count(*) FROM \"#{schema}\".tenants",
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
             Compatibility.baseline_versions()
  end

  test "adoption verifies a compatible Belimbing schema before recording baselines", %{
    schema: schema
  } do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    assert {:ok, :adopted} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)

    assert recorded_versions(MigrationTestRepo, schema) ==
             Compatibility.baseline_versions()

    assert {:ok, :already_adopted} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)
  end

  test "adoption advances a verified prefix from an earlier Bilimbi baseline", %{schema: schema} do
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
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

  defp drop_bilimbi_ledger!(repo, schema) do
    SQL.query!(repo, ~s(DROP TABLE "#{schema}".bilimbi_schema_migrations), [])
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
