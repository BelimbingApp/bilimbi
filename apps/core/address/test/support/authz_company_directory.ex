defmodule Bilimbi.Core.Address.AuthzCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def company_ids(%Scope{}), do: [73]

  @impl true
  def company_in_scope?(%Scope{tenant: %{id: 41}}, 73), do: true
  def company_in_scope?(%Scope{}, _company_id), do: false

  @impl true
  def company_writable(%Scope{} = scope, company_id),
    do: if(company_in_scope?(scope, company_id), do: :ok, else: {:error, :company_not_found})

  @impl true
  def companies_in_scope(%Scope{tenant: %{id: 41}}), do: [%{id: 73, name: "Address test company"}]
  def companies_in_scope(%Scope{}), do: []
end
