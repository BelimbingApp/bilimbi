defmodule Bilimbi.Core.Address.Summary do
  @moduledoc """
  Stable read model for a tenant-owned address.
  """

  @enforce_keys [:id, :tenant_id, :verification_status]
  defstruct [
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
    :admin1_code,
    :verification_status
  ]

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
          admin1_code: String.t() | nil,
          verification_status: String.t()
        }

  @doc false
  def from_schema(address) do
    %__MODULE__{
      id: address.id,
      tenant_id: address.tenant_id,
      label: address.label,
      phone: address.phone,
      line1: address.line1,
      line2: address.line2,
      line3: address.line3,
      locality: address.locality,
      postcode: address.postcode,
      country_iso: address.country_iso,
      admin1_code: address.admin1_code,
      verification_status: address.verification_status
    }
  end
end
