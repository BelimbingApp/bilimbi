defmodule Bilimbi.Core.Company.Summary do
  @moduledoc """
  Stable read model for presenting a tenant-owned company.

  Two of its fields are sensitive: `tax_id` and `email`, the registered tax
  identity and contact of a legal entity. Both read as the value only for a
  reader holding `admin.company.sensitive.view`; for anyone else
  `for_scope/2` puts a `Bilimbi.Base.Authz.Withheld` marker in their place
  (`field_policy/0`, the one declaration `Bilimbi.Core.Company` applies to
  every read, every update, its list search and its grid fields). A
  template renders the marker with `<.withheld>` and offers no editor.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.FieldPolicy
  alias Bilimbi.Base.Authz.Withheld
  alias Bilimbi.Base.Tenancy.Scope

  @sensitive_capability "admin.company.sensitive.view"
  @field_policy FieldPolicy.new!(tax_id: @sensitive_capability, email: @sensitive_capability)

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
          registration_number: String.t() | nil,
          tax_id: String.t() | Withheld.t() | nil,
          legal_entity_type_id: pos_integer() | nil,
          jurisdiction: String.t() | nil,
          email: String.t() | Withheld.t() | nil,
          website: String.t() | nil,
          scope_activities: map() | list() | nil,
          metadata: map() | nil
        }

  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{legal_name: legal_name, name: name}) do
    if present?(legal_name), do: legal_name, else: name
  end

  @doc """
  The fields a reader needs `admin.company.sensitive.view` to see.

  Core Company declares its sensitive columns once, here, and every surface
  that shows them reads this: `for_scope/2` for the read models, the update
  path for writes, the administration search for its columns, and
  `Bilimbi.Core.Company.GridTables` for the grid fields.
  """
  @spec field_policy() :: FieldPolicy.t()
  def field_policy, do: @field_policy

  @doc """
  The read model of one row, or of each row in a list, as `scope` may see it.

  This is where field-level authorization is enforced for companies: the
  summary is built from the row and then `Bilimbi.Base.Authz.redact/3`
  replaces every sensitive field the scope's actor lacks the capability for
  with a `Bilimbi.Base.Authz.Withheld` marker. There is no way to build a
  summary that skips it, so no caller of `Bilimbi.Core.Company` can obtain
  a withheld value, whatever it renders.
  """
  @spec for_scope(Bilimbi.Core.Company.Schema.t(), Scope.t()) :: t()
  @spec for_scope([Bilimbi.Core.Company.Schema.t()], Scope.t()) :: [t()]
  def for_scope(companies, %Scope{} = scope) when is_list(companies) do
    Authz.redact(scope, @field_policy, Enum.map(companies, &from_schema/1))
  end

  def for_scope(company, %Scope{} = scope) do
    Authz.redact(scope, @field_policy, from_schema(company))
  end

  defp from_schema(company) do
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
