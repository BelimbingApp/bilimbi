defmodule Bilimbi.Core.Company.AuthzCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Summary

  @impl true
  def company_ids(%Scope{} = scope) do
    {:ok, companies} = Company.list_companies(scope)
    Enum.map(companies, & &1.id)
  end

  # Same `list_companies/1` call as `company_ids/1` on purpose: the two lists
  # have to describe the same set, or a picker built from this one could offer a
  # company that `company_in_scope?/2` refuses.
  #
  # `display_name/1` rather than `.name` because `core/user`'s index already
  # names companies that way; disagreeing here would have two screens calling
  # one company two things. Sorting happens on the resulting string, not on
  # `name`, so the order matches what is actually rendered -- `list_companies/1`
  # orders by id and is left alone, since its other callers do not want this.
  @impl true
  def companies_in_scope(%Scope{} = scope) do
    {:ok, companies} = Company.list_companies(scope)

    companies
    |> Enum.map(&%{id: &1.id, name: Summary.display_name(&1)})
    |> Enum.sort_by(& &1.name)
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    match?({:ok, _company}, Company.get_company(scope, company_id))
  end

  def company_in_scope?(%Scope{}, _company_id), do: false
end
