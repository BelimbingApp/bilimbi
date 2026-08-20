defmodule Bilimbi.Core.Geonames.PostcodeIndex do
  @moduledoc "Postcode fields exposed by the read-only Postcodes index."

  @enforce_keys [:id, :country_iso, :postcode, :place_name]
  defstruct [
    :id,
    :country_iso,
    :country_name,
    :postcode,
    :place_name,
    :admin1_code,
    :latitude,
    :longitude,
    :accuracy,
    :provenance,
    :revision,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          country_iso: String.t(),
          country_name: String.t() | nil,
          postcode: String.t(),
          place_name: String.t(),
          admin1_code: String.t() | nil,
          latitude: Decimal.t() | nil,
          longitude: Decimal.t() | nil,
          accuracy: non_neg_integer() | nil,
          provenance: :geonames | :operator,
          revision: String.t(),
          updated_at: NaiveDateTime.t() | nil
        }

  @doc false
  def from_schema(postcode, country_name, override \\ nil) do
    %__MODULE__{
      id: postcode.id,
      country_iso: postcode.country_iso,
      country_name: country_name,
      postcode: postcode.postcode,
      place_name: postcode.place_name,
      admin1_code: postcode.admin1_code,
      latitude: postcode.latitude,
      longitude: postcode.longitude,
      accuracy: postcode.accuracy,
      provenance: if(override, do: :operator, else: :geonames),
      revision: revision(postcode, override),
      updated_at: postcode.updated_at
    }
  end

  defp revision(postcode, nil),
    do: Bilimbi.Core.Geonames.PostcodeOverrides.source_revision(postcode)

  defp revision(_postcode, override),
    do: Bilimbi.Core.Geonames.PostcodeOverrides.override_revision(override)
end
