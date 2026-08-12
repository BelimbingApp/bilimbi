defmodule Bilimbi.Core.Geonames.Admin1Summary do
  @moduledoc "Stable first-level administrative-division read model."

  @enforce_keys [:id, :code, :name, :country_iso]
  defstruct [:id, :code, :name, :alt_name, :geoname_id, :country_iso]

  @type t :: %__MODULE__{
          id: pos_integer(),
          code: String.t(),
          name: String.t(),
          alt_name: String.t() | nil,
          geoname_id: non_neg_integer() | nil,
          country_iso: String.t()
        }

  @doc false
  def from_schema(admin1) do
    %__MODULE__{
      id: admin1.id,
      code: admin1.code,
      name: admin1.name,
      alt_name: admin1.alt_name,
      geoname_id: admin1.geoname_id,
      country_iso: country_iso(admin1.code)
    }
  end

  defp country_iso(code), do: code |> String.split(".", parts: 2) |> hd()
end
