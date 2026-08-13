defmodule Bilimbi.Core.Address.Detail do
  @moduledoc "Stable detail read model for a tenant-owned address and its live owners."

  alias Bilimbi.Core.Address.LinkedOwner
  alias Bilimbi.Core.Address.Schema

  @fields [
    :id,
    :tenant_id,
    :label,
    :phone,
    :line1,
    :line2,
    :line3,
    :locality,
    :postcode,
    :country_iso,
    :country_name,
    :admin1_code,
    :admin1_name,
    :raw_input,
    :source,
    :source_ref,
    :parser_version,
    :parse_confidence,
    :parsed_at,
    :normalized_at,
    :normalization_notes,
    :verification_status,
    :metadata,
    :created_at,
    :updated_at,
    :linked_owners
  ]

  @enforce_keys [:id, :tenant_id, :verification_status, :linked_owners]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          label: String.t() | nil,
          phone: String.t() | nil,
          line1: String.t() | nil,
          line2: String.t() | nil,
          line3: String.t() | nil,
          locality: String.t() | nil,
          postcode: String.t() | nil,
          country_iso: String.t() | nil,
          country_name: String.t() | nil,
          admin1_code: String.t() | nil,
          admin1_name: String.t() | nil,
          raw_input: String.t() | nil,
          source: String.t() | nil,
          source_ref: String.t() | nil,
          parser_version: String.t() | nil,
          parse_confidence: Decimal.t() | nil,
          parsed_at: NaiveDateTime.t() | nil,
          normalized_at: NaiveDateTime.t() | nil,
          normalization_notes: term(),
          verification_status: String.t(),
          metadata: term(),
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil,
          linked_owners: [LinkedOwner.t()]
        }

  @doc false
  @spec from_schema(Schema.t(), String.t() | nil, String.t() | nil, [LinkedOwner.t()]) :: t()
  def from_schema(address, country_name, admin1_name, linked_owners) do
    address
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.merge(%{
      country_name: country_name,
      admin1_name: admin1_name,
      linked_owners: linked_owners
    })
    |> then(&struct!(__MODULE__, &1))
  end
end
