defmodule Bilimbi.Base.Workflow.TestCompanyDirectory do
  @moduledoc false
  @behaviour Bilimbi.Base.Authz.CompanyDirectory
  alias Bilimbi.Base.Tenancy.Scope
  @impl true
  def company_ids(scope), do: if(Scope.tenant_id(scope) == 1, do: [10], else: [])
  @impl true
  def company_in_scope?(scope, id), do: id in company_ids(scope)
  @impl true
  def companies_in_scope(scope),
    do: Enum.map(company_ids(scope), &%{id: &1, name: "Example company"})
end
