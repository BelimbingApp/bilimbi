defmodule Bilimbi.Core.CompatibilityBaseline do
  @moduledoc """
  Orchestrates the required Base and Core compatibility schema.

  Fresh databases run the owned Ecto migrations. Existing Belimbing databases
  must pass strict verification before their current state is recorded in
  Bilimbi's independent migration ledger.
  """

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.SchemaContract, as: TenancyContract
  alias Bilimbi.Core.Company.SchemaContract, as: CompanyContract
  alias Ecto.Adapters.SQL

  @migration_source "bilimbi_schema_migrations"
  @compatibility_source "e70b4d33c0b10790e681f4c2b5095d85a53bc918"

  def migration_source, do: @migration_source
  def compatibility_source, do: @compatibility_source

  def migration_paths do
    [
      Application.app_dir(:base, "priv/repo/migrations"),
      Application.app_dir(:core, "priv/repo/migrations")
    ]
  end

  def baseline_versions do
    [TenancyContract.migration_version(), CompanyContract.migration_version()]
  end

  def migration_entries do
    [
      {TenancyContract.migration_version(),
       Bilimbi.Base.Repo.Migrations.CreateBaseTenancyCompatibilityBaseline,
       Path.join(
         Enum.at(migration_paths(), 0),
         "20260811093951_create_base_tenancy_compatibility_baseline.exs"
       )},
      {CompanyContract.migration_version(),
       Bilimbi.Core.Migrations.CreateCoreCompanyCompatibilityBaseline,
       Path.join(
         Enum.at(migration_paths(), 1),
         "20260811093956_create_core_company_compatibility_baseline.exs"
       )}
    ]
    |> Enum.map(fn {version, module, path} ->
      Code.require_file(path)
      {version, module}
    end)
  end

  @spec migrate(Ecto.Repo.t(), keyword()) :: [integer()]
  def migrate(repo \\ Repo, opts \\ []) do
    opts = opts |> Keyword.put(:all, true) |> Keyword.put(:strict_version_order, true)
    Ecto.Migrator.run(repo, migration_entries(), :up, opts)
  end

  @spec verify(Ecto.Repo.t(), keyword()) :: :ok | {:error, [String.t()]}
  def verify(repo \\ Repo, opts \\ []) do
    table_specs = TenancyContract.tables() ++ CompanyContract.tables()

    with :ok <- SchemaVerifier.verify(repo, table_specs, opts) do
      verify_identity_invariants(repo, opts)
    end
  end

  @spec adopt(Ecto.Repo.t(), keyword()) ::
          {:ok, :adopted | :already_adopted}
          | {:error, {:schema_drift, [String.t()]} | {:ledger_conflict, [integer()]}}
  def adopt(repo \\ Repo, opts \\ []) do
    schema = Keyword.get(opts, :prefix, "public")
    validate_identifier!(schema)

    case repo.transaction(fn -> adopt_in_transaction(repo, schema, opts) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp adopt_in_transaction(repo, schema, opts) do
    SQL.query!(
      repo,
      "SELECT pg_advisory_xact_lock(hashtext($1))",
      ["bilimbi-schema-adoption:#{schema}"]
    )

    case verify(repo, opts) do
      :ok -> adopt_ledger(repo, schema)
      {:error, errors} -> repo.rollback({:schema_drift, errors})
    end
  end

  defp adopt_ledger(repo, schema) do
    case ledger_versions(repo, schema) do
      :missing ->
        create_ledger!(repo, schema)
        record_baselines!(repo, schema)
        {:ok, :adopted}

      [] ->
        record_baselines!(repo, schema)
        {:ok, :adopted}

      versions ->
        if versions == baseline_versions() do
          {:ok, :already_adopted}
        else
          repo.rollback({:ledger_conflict, versions})
        end
    end
  end

  defp ledger_versions(repo, schema) do
    qualified_name = "#{schema}.#{@migration_source}"

    case SQL.query!(repo, "SELECT to_regclass($1)::text", [qualified_name]).rows do
      [[nil]] ->
        :missing

      [[_table]] ->
        result =
          SQL.query!(
            repo,
            "SELECT version FROM #{quote_identifier(schema)}.#{quote_identifier(@migration_source)} ORDER BY version",
            []
          )

        Enum.map(result.rows, fn [version] -> version end)
    end
  end

  defp create_ledger!(repo, schema) do
    SQL.query!(
      repo,
      """
      CREATE TABLE #{quote_identifier(schema)}.#{quote_identifier(@migration_source)} (
        version bigint PRIMARY KEY,
        inserted_at timestamp(0) without time zone NOT NULL
      )
      """,
      []
    )
  end

  defp record_baselines!(repo, schema) do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    rows = Enum.map(baseline_versions(), &%{version: &1, inserted_at: now})

    {count, _} = repo.insert_all(@migration_source, rows, prefix: schema)

    if count != length(rows) do
      repo.rollback({:ledger_conflict, ledger_versions(repo, schema)})
    end
  end

  defp verify_identity_invariants(repo, opts) do
    schema = Keyword.get(opts, :prefix, "public")
    prefix = quote_identifier(schema)

    operator_errors =
      case SQL.query!(
             repo,
             "SELECT id, deleted_at FROM #{prefix}.tenants WHERE is_platform_operator ORDER BY id",
             []
           ).rows do
        [] ->
          []

        [[_tenant_id, nil]] ->
          []

        [[tenant_id, _deleted_at]] ->
          ["tenants: platform-operator tenant #{tenant_id} is soft-deleted"]

        rows ->
          ids = Enum.map_join(rows, ", ", fn [tenant_id, _deleted_at] -> tenant_id end)
          ["tenants: multiple platform operators are marked: #{ids}"]
      end

    assignment_errors =
      SQL.query!(
        repo,
        """
        SELECT assignment.tenant_id,
               assignment.company_id,
               tenant.id,
               tenant.deleted_at,
               company.id,
               company.tenant_id,
               company.deleted_at
        FROM #{prefix}.tenant_primary_companies AS assignment
        LEFT JOIN #{prefix}.tenants AS tenant
          ON tenant.id = assignment.tenant_id
        LEFT JOIN #{prefix}.companies AS company
          ON company.id = assignment.company_id
         AND company.tenant_id = assignment.tenant_id
        ORDER BY assignment.tenant_id
        """,
        []
      ).rows
      |> Enum.flat_map(&assignment_errors/1)

    case operator_errors ++ assignment_errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp assignment_errors([
         tenant_id,
         _company_id,
         nil,
         _tenant_deleted_at,
         _id,
         _owner,
         _deleted
       ]) do
    ["tenant_primary_companies: assignment for missing tenant #{tenant_id}"]
  end

  defp assignment_errors([tenant_id, _company_id, _id, deleted_at, _company, _owner, _deleted])
       when not is_nil(deleted_at) do
    ["tenant_primary_companies: assignment belongs to soft-deleted tenant #{tenant_id}"]
  end

  defp assignment_errors([tenant_id, company_id, _id, _deleted, nil, _owner, _company_deleted]) do
    [
      "tenant_primary_companies: company #{company_id} is missing or does not belong to tenant #{tenant_id}"
    ]
  end

  defp assignment_errors([
         tenant_id,
         _company_id,
         _id,
         _tenant_deleted,
         _company,
         owner,
         nil
       ])
       when tenant_id == owner do
    []
  end

  defp assignment_errors([tenant_id, company_id, _id, _tenant_deleted, _company, owner, nil]) do
    [
      "tenant_primary_companies: company #{company_id} belongs to tenant #{owner}, expected #{tenant_id}"
    ]
  end

  defp assignment_errors([
         tenant_id,
         company_id,
         _id,
         _tenant_deleted,
         _company,
         _owner,
         _deleted
       ]) do
    ["tenant_primary_companies: company #{company_id} for tenant #{tenant_id} is soft-deleted"]
  end

  defp quote_identifier(identifier), do: ~s("#{identifier}")

  defp validate_identifier!(identifier) do
    unless Regex.match?(~r/^[a-z_][a-z0-9_]*$/, identifier) do
      raise ArgumentError, "invalid PostgreSQL identifier: #{inspect(identifier)}"
    end
  end
end
