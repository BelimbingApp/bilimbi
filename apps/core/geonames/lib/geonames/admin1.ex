defmodule Bilimbi.Core.Geonames.Admin1 do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "geonames_admin1" do
    field :code, :string
    field :name, :string
    field :alt_name, :string
    field :geoname_id, :integer
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
