defmodule Bilimbi.Core.Geonames.Admin1Index do
  @moduledoc "Administrative-division fields exposed by the read-only Admin1 index."

  @enforce_keys [:id, :country_iso, :code, :name]
  defstruct [:id, :country_iso, :country_name, :code, :name, :alt_name, :updated_at]

  @type t :: %__MODULE__{
          id: pos_integer(),
          country_iso: String.t(),
          country_name: String.t() | nil,
          code: String.t(),
          name: String.t(),
          alt_name: String.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @doc false
  def from_schema(admin1, country_name) do
    %__MODULE__{
      id: admin1.id,
      country_iso: country_iso(admin1.code),
      country_name: country_name,
      code: admin1.code,
      name: admin1.name,
      alt_name: admin1.alt_name,
      updated_at: admin1.updated_at
    }
  end

  defp country_iso(code), do: code |> String.split(".", parts: 2) |> hd()
end
