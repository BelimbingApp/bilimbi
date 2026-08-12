defmodule Bilimbi.Core.Geonames.City do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "geonames_cities" do
    field :geoname_id, :integer
    field :name, :string
    field :ascii_name, :string
    field :alternate_names, :string
    field :latitude, :decimal
    field :longitude, :decimal
    field :country_iso, :string
    field :admin1_code, :string
    field :population, :integer, default: 0
    field :timezone, :string
    field :modification_date, :date
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
