defmodule Bilimbi.Core.Geonames.PostcodeSummary do
  @moduledoc "Stable postcode lookup result exposed by Core Geonames."

  @enforce_keys [:id, :country_iso, :postcode, :place_name]
  @fields [
    :id,
    :country_iso,
    :postcode,
    :place_name,
    :admin1_code,
    :admin_name1,
    :admin_code1,
    :admin_name2,
    :admin_code2,
    :admin_name3,
    :admin_code3,
    :latitude,
    :longitude,
    :accuracy
  ]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          country_iso: String.t(),
          postcode: String.t(),
          place_name: String.t(),
          admin1_code: String.t() | nil,
          admin_name1: String.t() | nil,
          admin_code1: String.t() | nil,
          admin_name2: String.t() | nil,
          admin_code2: String.t() | nil,
          admin_name3: String.t() | nil,
          admin_code3: String.t() | nil,
          latitude: Decimal.t() | nil,
          longitude: Decimal.t() | nil,
          accuracy: non_neg_integer() | nil
        }

  @doc false
  def from_schema(postcode) do
    struct!(__MODULE__, Map.take(Map.from_struct(postcode), @fields))
  end
end
