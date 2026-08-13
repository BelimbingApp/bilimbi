defmodule Bilimbi.Core.Geonames.PostcodeIndex do
  @moduledoc "Postcode fields exposed by the read-only Postcodes index."

  @enforce_keys [:id, :country_iso, :postcode, :place_name]
  defstruct [:id, :country_iso, :country_name, :postcode, :place_name, :admin1_code, :updated_at]

  @type t :: %__MODULE__{
          id: pos_integer(),
          country_iso: String.t(),
          country_name: String.t() | nil,
          postcode: String.t(),
          place_name: String.t(),
          admin1_code: String.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @doc false
  def from_schema(postcode, country_name) do
    %__MODULE__{
      id: postcode.id,
      country_iso: postcode.country_iso,
      country_name: country_name,
      postcode: postcode.postcode,
      place_name: postcode.place_name,
      admin1_code: postcode.admin1_code,
      updated_at: postcode.updated_at
    }
  end
end
