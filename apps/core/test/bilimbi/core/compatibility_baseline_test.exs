defmodule Bilimbi.Core.CompatibilityBaselineTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Core.CompatibilityBaseline
  alias Bilimbi.Core.MigrationTestRepo
  alias Ecto.Adapters.SQL

  setup do
    repo_options =
      Bilimbi.Base.Repo.config()
      |> Keyword.put(:name, MigrationTestRepo)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)

    Application.put_env(:base, MigrationTestRepo, repo_options)
    on_exit(fn -> Application.delete_env(:base, MigrationTestRepo) end)

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
    assert CompatibilityBaseline.migrate(MigrationTestRepo, prefix: schema, log: false) ==
             CompatibilityBaseline.baseline_versions()

    assert :ok = CompatibilityBaseline.verify(MigrationTestRepo, prefix: schema)

    assert [[0]] =
             SQL.query!(
               MigrationTestRepo,
               "SELECT count(*) FROM \"#{schema}\".tenants",
               []
             ).rows

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

    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") != nil
    assert relation(MigrationTestRepo, schema, "migrations") == nil

    assert recorded_versions(MigrationTestRepo, schema) ==
             CompatibilityBaseline.baseline_versions()
  end

  test "adoption verifies a compatible Belimbing schema before recording baselines", %{
    schema: schema
  } do
    CompatibilityBaseline.migrate(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    assert {:ok, :adopted} =
             CompatibilityBaseline.adopt(MigrationTestRepo, prefix: schema)

    assert recorded_versions(MigrationTestRepo, schema) ==
             CompatibilityBaseline.baseline_versions()

    assert {:ok, :already_adopted} =
             CompatibilityBaseline.adopt(MigrationTestRepo, prefix: schema)
  end

  test "adoption refuses schema drift and leaves no Bilimbi ledger", %{schema: schema} do
    CompatibilityBaseline.migrate(MigrationTestRepo, prefix: schema, log: false)
    drop_bilimbi_ledger!(MigrationTestRepo, schema)

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".companies DROP COLUMN legal_name),
      []
    )

    assert {:error, {:schema_drift, errors}} =
             CompatibilityBaseline.adopt(MigrationTestRepo, prefix: schema)

    assert "companies: missing column legal_name" in errors
    assert relation(MigrationTestRepo, schema, "bilimbi_schema_migrations") == nil
  end

  test "verification refuses a partial cross-module contribution", %{schema: schema} do
    CompatibilityBaseline.migrate(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".company_external_accesses ADD COLUMN user_id bigint),
      []
    )

    assert {:error, errors} = CompatibilityBaseline.verify(MigrationTestRepo, prefix: schema)

    assert "company_external_accesses: incomplete optional contribution core/user external-access owner" in errors
  end

  test "verification refuses the historical implicit tenant default", %{schema: schema} do
    CompatibilityBaseline.migrate(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      ~s(ALTER TABLE "#{schema}".companies ALTER COLUMN tenant_id SET DEFAULT 1),
      []
    )

    assert {:error, errors} = CompatibilityBaseline.verify(MigrationTestRepo, prefix: schema)
    assert "companies.tenant_id: incompatible default \"1\"" in errors
  end

  test "verification rejects a soft-deleted marked platform operator", %{schema: schema} do
    CompatibilityBaseline.migrate(MigrationTestRepo, prefix: schema, log: false)

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

    assert {:error, errors} = CompatibilityBaseline.verify(MigrationTestRepo, prefix: schema)
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
