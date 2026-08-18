defmodule Bilimbi.Core.Geonames.Country do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "geonames_countries" do
    field(:iso, :string)
    field(:iso3, :string)
    field(:iso_numeric, :string)
    field(:country, :string)
    field(:capital, :string)
    field(:area, :float)
    field(:population, :integer, default: 0)
    field(:continent, :string)
    field(:tld, :string)
    field(:currency_code, :string)
    field(:currency_name, :string)
    field(:phone, :string)
    field(:postal_code_format, :string)
    field(:postal_code_regex, :string)
    field(:languages, :string)
    field(:geoname_id, :integer)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def name_changeset(country, attrs) do
    country
    |> Ecto.Changeset.cast(attrs, [:country])
    |> Ecto.Changeset.validate_required([:country])
  end
end
