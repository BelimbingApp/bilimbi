defmodule Bilimbi.Base.Schedule.Run do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_schedule_runs" do
    field :source, :string, default: "scheduler"
    field :key, :string
    field :name, :string
    field :expression, :string
    field :status, :string
    field :started_at, :naive_datetime
    field :finished_at, :naive_datetime
    field :exit_code, :integer
    field :runtime_ms, :integer
    field :output_excerpt, :string
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
