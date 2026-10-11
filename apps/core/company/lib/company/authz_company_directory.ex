defmodule Bilimbi.Core.Company.AuthzCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Summary

  @impl true
  def company_ids(%Scope{} = scope) do
    {:ok, ids} = Company.list_live_company_ids(scope)
    ids
  end

  @impl true
  def live_company_ids_query(%Scope{} = scope) do
    Company.live_company_ids_query(scope)
  end

  # `companies_in_scope/1` still loads rows because a picker needs display
  # names. Its id set has to match `company_ids/1`, which now selects ids
  # only: a picker that offered a company `company_in_scope?/2` then rejected
  # would fail on submit for a value it supplied itself.
  #
  # `display_name/1` rather than `.name` because `core/user`'s index already
  # names companies that way; disagreeing here would have two screens calling
  # one company two things. Sorting happens on the resulting string, not on
  # `name`, so the order matches what is actually rendered -- `list_companies/1`
  # orders by id and is left alone, since its other callers do not want this.
  #
  # Sorted case-insensitively. Raw binary comparison is codepoint order, which
  # puts every lowercase initial after every uppercase one: "eMart Retail" would
  # land below "Zulu Holdings" in the dropdown. Belimbing got this free from the
  # database collation on `orderBy('name')`.
  @impl true
  def companies_in_scope(%Scope{} = scope) do
    {:ok, companies} = Company.list_companies(scope)

    companies
    |> Enum.map(&%{id: &1.id, name: Summary.display_name(&1)})
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    Company.live_company?(scope, company_id)
  end

  def company_in_scope?(%Scope{}, _company_id), do: false

  # The same rule every Core write follows (`Company.require_writable_company/2`),
  # so a role, an assignment or a grant in an archived company is refused the
  # way a department or an employee in it is.
  @impl true
  def company_writable(%Scope{} = scope, company_id) do
    case Company.require_writable_company(scope, company_id) do
      {:ok, _id} -> :ok
      {:error, :not_found} -> {:error, :company_not_found}
      {:error, :company_archived} -> {:error, :company_archived}
    end
  end
end
