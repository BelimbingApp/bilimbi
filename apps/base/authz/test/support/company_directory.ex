defmodule Bilimbi.Base.Authz.TestCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def company_ids(%Scope{} = scope) do
    case Scope.tenant_id(scope) do
      1 -> [10, 11]
      _tenant_id -> []
    end
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id) do
    company_id in company_ids(scope)
  end

  # Named off `company_ids/1` rather than from a second literal list, so the two
  # cannot disagree as this double grows companies. Names descend while ids
  # ascend, which keeps a test that only sorted by id from looking correct.
  @impl true
  def companies_in_scope(%Scope{} = scope) do
    scope
    |> company_ids()
    |> Enum.map(&%{id: &1, name: "Company #{100 - &1}"})
    |> Enum.sort_by(&String.downcase(&1.name))
  end
end
