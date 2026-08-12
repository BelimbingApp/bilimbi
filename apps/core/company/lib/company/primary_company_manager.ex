defmodule Bilimbi.Core.Company.PrimaryCompanyManager do
  @moduledoc """
  Resolves and changes explicit tenant-to-primary-company relationships.

  This manager owns Company meaning in Core. It never infers identity from a
  numeric ID or from the oldest company in a tenant.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.PrimaryCompanyInvariantError
  alias Bilimbi.Core.Company.PrimaryCompanyNotProvisionedError
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary
  alias Bilimbi.Core.Company.TenantPrimaryCompany

  @spec platform_operator_company!() :: Summary.t()
  def platform_operator_company! do
    Tenancy.require_platform_operator!()
    |> require_for_tenant!()
  end

  @spec find_for_tenant(Identity.t() | pos_integer()) :: Summary.t() | nil
  def find_for_tenant(tenant) do
    tenant = resolve_tenant!(tenant)
    find_for_resolved_tenant(tenant)
  end

  defp find_for_resolved_tenant(tenant) do
    query =
      from company in Tenancy.scope_query(Schema, Scope.for_tenant(tenant)),
        join: assignment in TenantPrimaryCompany,
        on:
          assignment.company_id == company.id and
            assignment.tenant_id == company.tenant_id,
        select:
          {%Summary{
             id: company.id,
             tenant_id: company.tenant_id,
             name: company.name,
             code: company.code,
             status: company.status,
             legal_name: company.legal_name
           }, company.deleted_at}

    case Repo.one(query) do
      nil ->
        if assignment_exists?(tenant.id) do
          raise PrimaryCompanyInvariantError,
            message:
              "the primary-company assignment references a missing or cross-tenant company",
            details: %{tenant_id: tenant.id}
        end

        nil

      {%Summary{} = company, nil} ->
        company

      {%Summary{id: company_id}, _deleted_at} ->
        raise PrimaryCompanyInvariantError,
          message: "the tenant primary company is soft-deleted",
          details: %{tenant_id: tenant.id, company_id: company_id}
    end
  end

  @spec require_for_tenant!(Identity.t() | pos_integer()) :: Summary.t()
  def require_for_tenant!(tenant) do
    tenant = resolve_tenant!(tenant)

    find_for_resolved_tenant(tenant) ||
      raise PrimaryCompanyNotProvisionedError, tenant_id: tenant.id
  end

  @spec primary?(Summary.t()) :: boolean()
  def primary?(%Summary{id: company_id, tenant_id: tenant_id}) do
    Repo.exists?(
      from assignment in TenantPrimaryCompany,
        where: assignment.tenant_id == ^tenant_id and assignment.company_id == ^company_id
    )
  end

  @type assignment_status :: :assigned | :unchanged | :transferred
  @type assignment_error ::
          :tenant_not_found
          | :tenant_soft_deleted
          | :company_not_found
          | :company_soft_deleted
          | {:company_tenant_mismatch, pos_integer()}
          | {:company_already_primary, pos_integer()}
          | {:already_assigned, pos_integer()}
          | Ecto.Changeset.t()

  @spec assign(Identity.t() | pos_integer(), Summary.t() | pos_integer()) ::
          {:ok, assignment_status()} | {:error, assignment_error()}
  def assign(tenant, company), do: write_assignment(tenant, company, false)

  @spec transfer(Identity.t() | pos_integer(), Summary.t() | pos_integer()) ::
          {:ok, assignment_status()} | {:error, assignment_error()}
  def transfer(tenant, company), do: write_assignment(tenant, company, true)

  @spec provision_tenant(map(), map()) ::
          {:ok, %{tenant: Identity.t(), company: Summary.t()}} | {:error, Ecto.Changeset.t()}
  def provision_tenant(tenant_attributes, company_attributes) do
    Repo.transaction(fn ->
      with {:ok, tenant} <- Tenancy.create_tenant(tenant_attributes),
           {:ok, company} <- insert_company(tenant.id, company_attributes),
           {:ok, _assignment} <- insert_assignment(tenant.id, company.id) do
        %{tenant: tenant, company: Summary.from_schema(company)}
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec provision_platform_operator(String.t() | nil, map()) ::
          {:ok,
           %{
             tenant: Identity.t(),
             company: Summary.t(),
             tenant_status: :created | :existing,
             company_status: :created | :existing
           }}
          | {:error, Ecto.Changeset.t()}
  def provision_platform_operator(tenant_name, company_attributes) do
    Repo.transaction(fn ->
      {:ok, tenant, tenant_status} = Tenancy.provision_platform_operator(tenant_name)
      _tenant = lock_tenant!(tenant.id)

      case locked_assignment(tenant.id) do
        nil ->
          with {:ok, company} <- insert_company(tenant.id, company_attributes),
               {:ok, _assignment} <- insert_assignment(tenant.id, company.id) do
            %{
              tenant: tenant,
              company: Summary.from_schema(company),
              tenant_status: tenant_status,
              company_status: :created
            }
          else
            {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
          end

        %TenantPrimaryCompany{} ->
          %{
            tenant: tenant,
            company: require_for_tenant!(tenant),
            tenant_status: tenant_status,
            company_status: :existing
          }
      end
    end)
  end

  defp write_assignment(tenant, company, allow_transfer?) do
    tenant_id = tenant_id(tenant)
    company_id = company_id(company)

    Repo.transaction(fn ->
      tenant = lock_tenant!(tenant_id)
      company = lock_company!(company_id)
      validate_company_owner!(tenant, company)
      validate_company_available!(tenant.id, company.id)

      case locked_assignment(tenant.id) do
        nil ->
          case insert_assignment(tenant.id, company.id) do
            {:ok, _assignment} -> :assigned
            {:error, changeset} -> Repo.rollback(changeset)
          end

        %TenantPrimaryCompany{company_id: ^company_id} ->
          :unchanged

        %TenantPrimaryCompany{company_id: current_company_id} = assignment ->
          if allow_transfer? do
            case assignment
                 |> TenantPrimaryCompany.transfer_changeset(company.id)
                 |> Repo.update() do
              {:ok, _assignment} -> :transferred
              {:error, changeset} -> Repo.rollback(changeset)
            end
          else
            Repo.rollback({:already_assigned, current_company_id})
          end
      end
    end)
  end

  defp insert_company(tenant_id, attributes) do
    tenant_id
    |> Schema.creation_changeset(attributes)
    |> Repo.insert()
  end

  defp insert_assignment(tenant_id, company_id) do
    tenant_id
    |> TenantPrimaryCompany.assignment_changeset(company_id)
    |> Repo.insert()
  end

  defp lock_tenant!(tenant_id) do
    case Tenancy.lock_tenant(tenant_id) do
      {:ok, tenant} -> tenant
      {:error, :not_found} -> Repo.rollback(:tenant_not_found)
      {:error, :soft_deleted} -> Repo.rollback(:tenant_soft_deleted)
    end
  end

  defp lock_company!(company_id) do
    query = from company in Schema, where: company.id == ^company_id, lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> Repo.rollback(:company_not_found)
      %Schema{deleted_at: nil} = company -> company
      %Schema{} -> Repo.rollback(:company_soft_deleted)
    end
  end

  defp locked_assignment(tenant_id) do
    Repo.one(
      from assignment in TenantPrimaryCompany,
        where: assignment.tenant_id == ^tenant_id,
        lock: "FOR UPDATE"
    )
  end

  defp validate_company_owner!(tenant, company) do
    if company.tenant_id != tenant.id do
      Repo.rollback({:company_tenant_mismatch, company.tenant_id})
    end
  end

  defp validate_company_available!(tenant_id, company_id) do
    query =
      from assignment in TenantPrimaryCompany,
        where: assignment.company_id == ^company_id and assignment.tenant_id != ^tenant_id,
        select: assignment.tenant_id,
        lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> :ok
      other_tenant_id -> Repo.rollback({:company_already_primary, other_tenant_id})
    end
  end

  defp tenant_id(%Identity{id: tenant_id}), do: tenant_id
  defp tenant_id(tenant_id) when is_integer(tenant_id) and tenant_id > 0, do: tenant_id

  defp company_id(%Summary{id: company_id}), do: company_id
  defp company_id(company_id) when is_integer(company_id) and company_id > 0, do: company_id

  defp resolve_tenant!(%Identity{} = tenant), do: tenant

  defp resolve_tenant!(tenant_id) when is_integer(tenant_id) and tenant_id > 0 do
    case Tenancy.fetch_tenant(tenant_id) do
      {:ok, tenant} ->
        tenant

      {:error, :not_found} ->
        raise PrimaryCompanyInvariantError,
          message: "the referenced tenant does not exist",
          details: %{tenant_id: tenant_id}

      {:error, :soft_deleted} ->
        raise PrimaryCompanyInvariantError,
          message: "the referenced tenant is soft-deleted",
          details: %{tenant_id: tenant_id}
    end
  end

  defp assignment_exists?(tenant_id) do
    Repo.exists?(
      from assignment in TenantPrimaryCompany,
        where: assignment.tenant_id == ^tenant_id
    )
  end
end
