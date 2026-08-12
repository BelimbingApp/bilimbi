defmodule Bilimbi.Core.Geonames.Postcode do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "geonames_postcodes" do
    field :country_iso, :string
    field :postcode, :string
    field :place_name, :string
    field :admin1_code, :string, source: :admin1Code
    field :admin_name1, :string
    field :admin_code1, :string
    field :admin_name2, :string
    field :admin_code2, :string
    field :admin_name3, :string
    field :admin_code3, :string
    field :latitude, :decimal
    field :longitude, :decimal
    field :accuracy, :integer
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
