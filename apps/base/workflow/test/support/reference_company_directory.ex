defmodule Bilimbi.Base.Workflow.ReferenceCompanyDirectory do
  @moduledoc false
  @behaviour Bilimbi.Base.Authz.CompanyDirectory
  alias Bilimbi.Base.Tenancy.{Actor, Scope}

  @impl true
  def company_ids(scope) do
    case Scope.actor(scope) do
      %Actor{type: :user, company_id: company_id} when is_integer(company_id) -> [company_id]
      _ -> []
    end
  end

  @impl true
  def company_in_scope?(scope, company_id), do: company_id in company_ids(scope)

  @impl true
  def companies_in_scope(scope),
    do: Enum.map(company_ids(scope), &%{id: &1, name: "Reference company"})
end
