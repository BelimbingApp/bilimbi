defmodule Bilimbi.Base.Schedule.TestCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def company_ids(%Scope{tenant: %{id: 41}}), do: [73]
  def company_ids(%Scope{}), do: []

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id), do: company_id in company_ids(scope)

  @impl true
  def companies_in_scope(%Scope{} = scope) do
    scope
    |> company_ids()
    |> Enum.map(&%{id: &1, name: "Schedule test company"})
  end
end
