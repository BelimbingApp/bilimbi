defmodule Bilimbi.Core.Geonames.CitySummary do
  @moduledoc "Stable city read model exposed by Core Geonames."

  @enforce_keys [
    :id,
    :geoname_id,
    :name,
    :ascii_name,
    :latitude,
    :longitude,
    :country_iso,
    :population,
    :timezone
  ]
  @fields [
    :id,
    :geoname_id,
    :name,
    :ascii_name,
    :alternate_names,
    :latitude,
    :longitude,
    :country_iso,
    :admin1_code,
    :population,
    :timezone,
    :modification_date
  ]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          geoname_id: pos_integer(),
          name: String.t(),
          ascii_name: String.t(),
          alternate_names: String.t() | nil,
          latitude: Decimal.t(),
          longitude: Decimal.t(),
          country_iso: String.t(),
          admin1_code: String.t() | nil,
          population: non_neg_integer(),
          timezone: String.t(),
          modification_date: Date.t() | nil
        }

  @doc false
  def from_schema(city) do
    struct!(__MODULE__, Map.take(Map.from_struct(city), @fields))
  end
end
