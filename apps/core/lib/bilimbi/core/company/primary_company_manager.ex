defmodule Bilimbi.Core.Company.PrimaryCompanyManager do
  @moduledoc """
  Resolves explicit tenant-to-primary-company relationships.

  This manager owns Company meaning in Core. It never infers identity from a
  numeric ID or from the oldest company in a tenant.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Tenant
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

  @spec find_for_tenant(Tenant.t() | pos_integer()) :: Summary.t() | nil
  def find_for_tenant(tenant) do
    tenant = resolve_tenant!(tenant)

    query =
      from company in Schema,
        join: assignment in TenantPrimaryCompany,
        on:
          assignment.company_id == company.id and
            assignment.tenant_id == company.tenant_id,
        where: assignment.tenant_id == ^tenant.id,
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

  @spec require_for_tenant!(Tenant.t() | pos_integer()) :: Summary.t()
  def require_for_tenant!(tenant) do
    tenant = resolve_tenant!(tenant)

    find_for_tenant(tenant) ||
      raise PrimaryCompanyNotProvisionedError, tenant_id: tenant.id
  end

  @spec primary?(Summary.t()) :: boolean()
  def primary?(%Summary{id: company_id, tenant_id: tenant_id}) do
    Repo.exists?(
      from assignment in TenantPrimaryCompany,
        where: assignment.tenant_id == ^tenant_id and assignment.company_id == ^company_id
    )
  end

  defp resolve_tenant!(%Tenant{id: tenant_id}), do: resolve_tenant!(tenant_id)

  defp resolve_tenant!(tenant_id) when is_integer(tenant_id) and tenant_id > 0 do
    case Repo.get(Tenant, tenant_id) do
      nil ->
        raise PrimaryCompanyInvariantError,
          message: "the referenced tenant does not exist",
          details: %{tenant_id: tenant_id}

      %Tenant{deleted_at: nil} = tenant ->
        tenant

      %Tenant{} ->
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
