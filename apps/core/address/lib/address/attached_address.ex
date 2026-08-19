defmodule Bilimbi.Core.Address.AttachedAddress do
  @moduledoc """
  Stable read model for an address attached to an owner (Company or Employee) with pivot metadata.
  """

  @enforce_keys [:id, :tenant_id, :attachment_id]
  defstruct [
    :id,
    :tenant_id,
    :attachment_id,
    :label,
    :phone,
    :line1,
    :line2,
    :line3,
    :locality,
    :postcode,
    :country_iso,
    :admin1_code,
    :verification_status,
    :kind,
    :is_primary,
    :priority,
    :valid_from,
    :valid_to
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          attachment_id: pos_integer(),
          label: String.t() | nil,
          phone: String.t() | nil,
          line1: String.t() | nil,
          line2: String.t() | nil,
          line3: String.t() | nil,
          locality: String.t() | nil,
          postcode: String.t() | nil,
          country_iso: String.t() | nil,
          admin1_code: String.t() | nil,
          verification_status: String.t(),
          kind: [String.t()],
          is_primary: boolean(),
          priority: integer(),
          valid_from: Date.t() | nil,
          valid_to: Date.t() | nil
        }

  @doc false
  def from_schema(address, attachment) do
    %__MODULE__{
      id: address.id,
      tenant_id: address.tenant_id,
      attachment_id: attachment.id,
      label: address.label,
      phone: address.phone,
      line1: address.line1,
      line2: address.line2,
      line3: address.line3,
      locality: address.locality,
      postcode: address.postcode,
      country_iso: address.country_iso,
      admin1_code: address.admin1_code,
      verification_status: address.verification_status,
      kind: attachment.kind || [],
      is_primary: attachment.is_primary || false,
      priority: attachment.priority || 0,
      valid_from: attachment.valid_from,
      valid_to: attachment.valid_to
    }
  end
end
