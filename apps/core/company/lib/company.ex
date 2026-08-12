defmodule Bilimbi.Core.Company do
  @moduledoc """
  Public API for the required Company business Module.

  The first compatibility slice exposes explicit primary-company identity
  while keeping Ecto schemas and query details private to this Module.
  """

  import Ecto.Query

  require Logger

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError, as: TenantInvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError, as: TenantNotProvisionedError
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.PrimaryCompanyInvariantError
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.PrimaryCompanyNotProvisionedError
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary

  @type lookup_error :: :not_provisioned | :invariant_violation | :database_unavailable

  @spec get_company(Scope.t(), pos_integer()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_company(%Scope{} = scope, company_id) do
    query =
      from company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      company -> {:ok, Summary.from_schema(company)}
    end
  end

  @spec platform_operator_company() :: {:ok, Summary.t()} | {:error, lookup_error()}
  def platform_operator_company do
    {:ok, PrimaryCompanyManager.platform_operator_company!()}
  rescue
    error in [TenantNotProvisionedError, PrimaryCompanyNotProvisionedError] ->
      Logger.info("platform operator is not fully provisioned: #{Exception.message(error)}")
      {:error, :not_provisioned}

    error in [TenantInvariantError, PrimaryCompanyInvariantError] ->
      Logger.error("platform operator identity is invalid: #{Exception.message(error)}")
      {:error, :invariant_violation}

    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("platform operator company lookup unavailable: #{Exception.message(error)}")
      {:error, :database_unavailable}
  end

  @doc """
  Assigns a tenant's primary company.

  The scope proves the tenant was live when the unit of work began. The manager
  still locks the tenant row inside its transaction, so a tenant deleted in the
  meantime is reported rather than assumed away.
  """
  @spec assign_primary_company(Scope.t(), pos_integer()) ::
          {:ok, PrimaryCompanyManager.assignment_status()}
          | {:error, PrimaryCompanyManager.assignment_error()}
  def assign_primary_company(%Scope{} = scope, company_id) do
    PrimaryCompanyManager.assign(Scope.tenant(scope), company_id)
  end

  @spec transfer_primary_company(Scope.t(), pos_integer()) ::
          {:ok, PrimaryCompanyManager.assignment_status()}
          | {:error, PrimaryCompanyManager.assignment_error()}
  def transfer_primary_company(%Scope{} = scope, company_id) do
    PrimaryCompanyManager.transfer(Scope.tenant(scope), company_id)
  end

  @spec addressable_identity() :: String.t()
  def addressable_identity, do: "App\\Core\\Company\\Models\\Company"

  @doc "Whether a department belongs to the requested tenant-owned company."
  @spec department_belongs_to_company?(Scope.t(), pos_integer(), pos_integer()) :: boolean()
  def department_belongs_to_company?(%Scope{} = scope, company_id, department_id)
      when is_integer(department_id) and department_id > 0 do
    case get_company(scope, company_id) do
      {:ok, _company} ->
        Repo.exists?(
          from(department in Department,
            where: department.id == ^department_id and department.company_id == ^company_id
          )
        )

      {:error, :not_found} ->
        false
    end
  end

  def department_belongs_to_company?(%Scope{}, _company_id, _department_id), do: false

  @spec provision_tenant(map(), map()) ::
          {:ok, %{tenant: Bilimbi.Base.Tenancy.Identity.t(), company: Summary.t()}}
          | {:error, Ecto.Changeset.t()}
  def provision_tenant(tenant_attributes, company_attributes) do
    PrimaryCompanyManager.provision_tenant(tenant_attributes, company_attributes)
  end

  @spec provision_platform_operator(String.t() | nil, map()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def provision_platform_operator(tenant_name, company_attributes) do
    PrimaryCompanyManager.provision_platform_operator(tenant_name, company_attributes)
  end
end
