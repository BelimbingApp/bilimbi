defmodule Bilimbi.Core.Company.TenantPrimaryCompany do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:tenant_id, :id, autogenerate: false}

  schema "tenant_primary_companies" do
    field :company_id, :id
  end

  @spec assignment_changeset(pos_integer(), pos_integer()) :: Ecto.Changeset.t()
  def assignment_changeset(tenant_id, company_id) do
    %__MODULE__{}
    |> change(tenant_id: tenant_id, company_id: company_id)
    |> apply_constraints()
  end

  @spec transfer_changeset(t(), pos_integer()) :: Ecto.Changeset.t()
  def transfer_changeset(%__MODULE__{} = assignment, company_id) do
    assignment
    |> change(company_id: company_id)
    |> apply_constraints()
  end

  @type t :: %__MODULE__{tenant_id: pos_integer(), company_id: pos_integer()}

  defp apply_constraints(changeset) do
    changeset
    |> unique_constraint(:tenant_id, name: :tenant_primary_companies_pkey)
    |> unique_constraint(:company_id, name: :tenant_primary_companies_company_id_unique)
    |> foreign_key_constraint(:tenant_id, name: :tenant_primary_companies_tenant_foreign)
    |> foreign_key_constraint(:company_id,
      name: :tenant_primary_companies_company_tenant_foreign
    )
  end
end
