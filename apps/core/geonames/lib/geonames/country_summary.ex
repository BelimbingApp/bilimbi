defmodule Bilimbi.Core.Geonames.CountrySummary do
  @moduledoc "Stable country read model exposed by Core Geonames."

  @enforce_keys [:id, :iso, :iso3, :iso_numeric, :country, :population, :continent]
  @fields [
    :id,
    :iso,
    :iso3,
    :iso_numeric,
    :country,
    :capital,
    :area,
    :population,
    :continent,
    :tld,
    :currency_code,
    :currency_name,
    :phone,
    :postal_code_format,
    :postal_code_regex,
    :languages,
    :geoname_id
  ]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          iso: String.t(),
          iso3: String.t(),
          iso_numeric: String.t(),
          country: String.t(),
          capital: String.t() | nil,
          area: float() | nil,
          population: non_neg_integer(),
          continent: String.t(),
          tld: String.t() | nil,
          currency_code: String.t() | nil,
          currency_name: String.t() | nil,
          phone: String.t() | nil,
          postal_code_format: String.t() | nil,
          postal_code_regex: String.t() | nil,
          languages: String.t() | nil,
          geoname_id: non_neg_integer() | nil
        }

  @doc false
  def from_schema(country) do
    struct!(__MODULE__, Map.take(Map.from_struct(country), @fields))
  end
end
