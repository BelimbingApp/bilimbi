defmodule Bilimbi.Core.Company.AuthzCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company

  @impl true
  def company_ids(%Scope{} = scope) do
    {:ok, companies} = Company.list_companies(scope)
    Enum.map(companies, & &1.id)
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    match?({:ok, _company}, Company.get_company(scope, company_id))
  end

  def company_in_scope?(%Scope{}, _company_id), do: false
end
