defmodule Bilimbi.Core.Geonames.Grid.CountriesSource do
  @moduledoc "The countries, global reference data keyed by ISO code, for the grid catalog."

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Core.Geonames.Country

  @impl true
  def query(_scope) do
    from(c in Country,
      select: %{
        iso: c.iso,
        iso3: c.iso3,
        country: c.country,
        capital: c.capital,
        continent: c.continent,
        population: c.population,
        area: c.area,
        currency_code: c.currency_code,
        phone: c.phone
      }
    )
  end
end
