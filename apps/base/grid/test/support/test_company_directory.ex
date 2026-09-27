defmodule Bilimbi.Base.Grid.TestCompanyDirectory do
  @moduledoc false

  # The authz validator requires the company directory to belong to the
  # package that declares it, so the grid tests carry their own: tenant 1
  # holds companies 10 and 11, tenant 2 holds company 20.
  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def company_ids(%Scope{} = scope) do
    case Scope.tenant_id(scope) do
      1 -> [10, 11]
      2 -> [20]
      _tenant_id -> []
    end
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id), do: company_id in company_ids(scope)

  @impl true
  def companies_in_scope(%Scope{} = scope) do
    scope |> company_ids() |> Enum.map(&%{id: &1, name: "Company #{&1}"})
  end
end
