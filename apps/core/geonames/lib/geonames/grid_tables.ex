defmodule Bilimbi.Core.Geonames.GridTables do
  @moduledoc "What Core Geonames puts in the grid catalog: `countries`, keyed by ISO code."

  alias Bilimbi.Core.Geonames.Grid.CountriesSource

  @doc false
  def tables do
    %{
      tables: [
        %{
          id: "countries",
          label: "Countries",
          capability: "admin.geonames.list",
          source: CountriesSource,
          key: "iso",
          label_field: "country",
          fields: [
            %{id: "iso", label: "ISO", type: :string},
            %{id: "iso3", label: "ISO 3", type: :string},
            %{id: "country", label: "Name", type: :string},
            %{id: "capital", label: "Capital", type: :string},
            %{id: "continent", label: "Continent", type: :string},
            %{id: "population", label: "Population", type: :integer},
            %{id: "area", label: "Area", type: :float},
            %{id: "currency_code", label: "Currency", type: :string},
            %{id: "phone", label: "Phone code", type: :string}
          ]
        }
      ]
    }
  end
end
