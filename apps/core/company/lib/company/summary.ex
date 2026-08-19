defmodule Bilimbi.Core.Company.Summary do
  @moduledoc """
  Stable read model for presenting a tenant-owned company.
  """

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
          tax_id: String.t() | nil,
          legal_entity_type_id: pos_integer() | nil,
          jurisdiction: String.t() | nil,
          email: String.t() | nil,
          website: String.t() | nil,
          scope_activities: map() | list() | nil,
          metadata: map() | nil
        }

  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{legal_name: legal_name, name: name}) do
    if present?(legal_name), do: legal_name, else: name
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
