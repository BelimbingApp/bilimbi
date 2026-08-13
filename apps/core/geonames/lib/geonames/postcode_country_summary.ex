defmodule Bilimbi.Core.Geonames.PostcodeCountrySummary do
  @moduledoc "Imported-postcode count grouped by country for the read-only Postcodes index."

  @enforce_keys [:country_iso, :country_name, :record_count]
  defstruct [:country_iso, :country_name, :record_count]

  @type t :: %__MODULE__{
          country_iso: String.t(),
          country_name: String.t(),
          record_count: non_neg_integer()
        }

  @doc false
  def new(country_iso, country_name, record_count) do
    %__MODULE__{
      country_iso: country_iso,
      country_name: country_name || country_iso,
      record_count: record_count
    }
  end
end
