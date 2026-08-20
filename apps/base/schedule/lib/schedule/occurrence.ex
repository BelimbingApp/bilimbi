defmodule Bilimbi.Base.Schedule.Occurrence do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "base_schedule_occurrences" do
    field :source, :string
    field :key, :string
    field :intended_at, :utc_datetime_usec
    field :trigger, :string
    field :overlap_key, :string
    field :state, :string
    field :job_id, :integer
    field :claimed_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
  end

  def claim_changeset(attributes) do
    %__MODULE__{}
    |> cast(attributes, [:source, :key, :intended_at, :trigger, :overlap_key, :state, :claimed_at])
    |> validate_required([:source, :key, :intended_at, :trigger, :state, :claimed_at])
    |> validate_inclusion(:trigger, ["manual", "scheduled"])
    |> validate_inclusion(:state, ["queued"])
    |> unique_constraint([:source, :key, :intended_at, :trigger],
      name: :base_schedule_occurrences_intended_unique
    )
    |> unique_constraint(:overlap_key, name: :base_schedule_occurrences_active_overlap_unique)
  end

  def job_changeset(occurrence, job_id) do
    change(occurrence, job_id: job_id)
  end
end
