defmodule Bilimbi.Core.Company.TenantPrimaryCompany do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:tenant_id, :id, autogenerate: false}

  schema "tenant_primary_companies" do
    field :company_id, :id
  end
end
