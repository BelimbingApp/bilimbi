defmodule Bilimbi.Core.Geonames.CountryOption do
  @moduledoc "Country option available to the Admin1 index filter."

  @enforce_keys [:iso, :country]
  defstruct [:iso, :country]

  @type t :: %__MODULE__{iso: String.t(), country: String.t()}

  @doc false
  def new(iso, country), do: %__MODULE__{iso: iso, country: country}
end
