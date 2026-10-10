defmodule Bilimbi.Core.Company.Summary do
  @moduledoc """
  Stable read model for presenting a tenant-owned company.

  Every summary `Bilimbi.Core.Company` returns is built through
  `for_scope/2`, which applies the tenant's field access restrictions
  (`Bilimbi.Base.Authz.restricted_fields/2` for the `companies` catalog
  table): a field an operator restricted for a role the reader holds carries a
  `Bilimbi.Base.Authz.Restricted` marker instead of its value, and a
  template renders it with `<.restricted>` and offers no editor.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Restricted
  alias Bilimbi.Base.Tenancy.Scope

  @table_id "companies"

  @enforce_keys [:id, :tenant_id, :name, :code, :status]
  defstruct [
    :id,
    :tenant_id,
    :parent_id,
    :name,
    :code,
    :status,
    :legal_name,
    :registration_number,
    :tax_id,
    :legal_entity_type_id,
    :jurisdiction,
    :email,
    :website,
    :scope_activities,
    :metadata
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          parent_id: pos_integer() | nil,
          name: String.t(),
          code: String.t(),
          status: String.t(),
          legal_name: String.t() | nil,
          registration_number: String.t() | Restricted.t() | nil,
          tax_id: String.t() | Restricted.t() | nil,
          legal_entity_type_id: pos_integer() | nil,
          jurisdiction: String.t() | Restricted.t() | nil,
          email: String.t() | Restricted.t() | nil,
          website: String.t() | Restricted.t() | nil,
          scope_activities: map() | list() | nil,
          metadata: map() | nil
        }

  @doc """
  The name a header or workspace strip shows: the legal name when there is
  one, otherwise the name. Takes the summary or any map carrying those two
  keys, such as the row `Bilimbi.Core.Company.identity/2` selects.
  """
  @spec display_name(%{legal_name: String.t() | nil, name: String.t()}) :: String.t()
  def display_name(%{legal_name: legal_name, name: name}) do
    if present?(legal_name), do: legal_name, else: name
  end

  @doc "The grid catalog table whose restrictions govern this read model."
  @spec table_id() :: String.t()
  def table_id, do: @table_id

  @doc """
  The read model of one row, or of each row in a list, as `scope` may see it.

  This is where field access restrictions are enforced for companies: the
  summary is built from the row and `Bilimbi.Base.Authz.redact/3` replaces
  every restricted field the scope's actor may not see with a `Restricted`
  marker. `Bilimbi.Core.Company` builds every summary it returns through
  this, so no caller obtains a value the reader may not have.
  """
  @spec for_scope(Bilimbi.Core.Company.Schema.t(), Scope.t()) :: t()
  @spec for_scope([Bilimbi.Core.Company.Schema.t()], Scope.t()) :: [t()]
  def for_scope(companies, %Scope{} = scope) when is_list(companies) do
    Authz.redact(scope, @table_id, Enum.map(companies, &from_schema/1))
  end

  def for_scope(company, %Scope{} = scope) do
    Authz.redact(scope, @table_id, from_schema(company))
  end

  @doc false
  @spec from_schema(Bilimbi.Core.Company.Schema.t()) :: t()
  def from_schema(company) do
    %__MODULE__{
      id: company.id,
      tenant_id: company.tenant_id,
      parent_id: company.parent_id,
      name: company.name,
      code: company.code,
      status: company.status,
      legal_name: company.legal_name,
      registration_number: company.registration_number,
      tax_id: company.tax_id,
      legal_entity_type_id: company.legal_entity_type_id,
      jurisdiction: company.jurisdiction,
      email: company.email,
      website: company.website,
      scope_activities: company.scope_activities,
      metadata: company.metadata
    }
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
