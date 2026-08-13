defmodule Bilimbi.Core.Geonames.CountryIndex do
  @moduledoc "Country fields exposed by the read-only Countries index."

  @enforce_keys [:id, :iso, :country, :population]
  defstruct [:id, :iso, :country, :capital, :phone, :currency_code, :population, :updated_at]

  @type t :: %__MODULE__{
          id: pos_integer(),
          iso: String.t(),
          country: String.t(),
          capital: String.t() | nil,
          phone: String.t() | nil,
          currency_code: String.t() | nil,
          population: non_neg_integer(),
          updated_at: NaiveDateTime.t() | nil
        }

  @doc false
  def from_schema(country) do
    %__MODULE__{
      id: country.id,
      iso: country.iso,
      country: country.country,
      capital: country.capital,
      phone: country.phone,
      currency_code: country.currency_code,
      population: country.population,
      updated_at: country.updated_at
    }
  end
end
