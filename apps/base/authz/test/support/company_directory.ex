defmodule Bilimbi.Base.Authz.TestCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

  @archived_company_id 13

  @impl true
  def company_ids(%Scope{} = scope) do
    case Scope.tenant_id(scope) do
      1 -> [10, 11, @archived_company_id]
      _tenant_id -> []
    end
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id) do
    company_id in company_ids(scope)
  end

  # Company 13 stands in for an archived company: in scope, so every read
  # still sees it, but refused by every write.
  @spec archived_company_id() :: pos_integer()
  def archived_company_id, do: @archived_company_id

  @impl true
  def company_writable(%Scope{} = scope, company_id) do
    cond do
      not company_in_scope?(scope, company_id) -> {:error, :company_not_found}
      company_id == @archived_company_id -> {:error, :company_archived}
      true -> :ok
    end
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
