defmodule Bilimbi.Base.Schedule.Suppression do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_schedule_suppressions" do
    field :source, :string, default: "scheduler"
    field :key, :string
    field :name, :string
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
