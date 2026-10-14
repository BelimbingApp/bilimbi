defmodule Bilimbi.Base.Artifacts.RetentionEvent do
  @moduledoc false
  # One append-only row per retention change. PostgreSQL stamps `recorded_at`
  # and refuses every update, delete and truncate (the migration's
  # `base_artifact_retention_events_guard` trigger), so the ledger records what
  # the database saw, not what the application claims.
  use Ecto.Schema
  import Ecto.Changeset

  @events ~w(retained retention_extended hold_placed hold_released)
  @actor_types ~w(user guest system)

  @primary_key {:id, :id, autogenerate: true}
  schema "base_artifact_retention_events" do
    field(:artifact_id, :binary_id)
    field(:tenant_id, :integer)
    field(:company_id, :integer)
    field(:owner_id, :string)
    field(:event, :string)
    field(:retain_until, :utc_datetime_usec)
    field(:legal_hold, :boolean)
    field(:reason, :string)
    field(:actor_type, :string)
    field(:actor_id, :integer)
    field(:impersonator_id, :integer)
    field(:system_principal, :string)
    field(:recorded_at, :utc_datetime_usec, read_after_writes: true)
  end

  @doc false
  def events, do: @events

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> validate_required([
      :artifact_id,
      :tenant_id,
      :company_id,
      :owner_id,
      :event,
      :retain_until,
      :legal_hold,
      :actor_type,
      :actor_id
    ])
    |> validate_inclusion(:event, @events)
    |> validate_inclusion(:actor_type, @actor_types)
    |> validate_length(:reason, max: 255)
    |> validate_length(:system_principal, max: 100)
    |> check_constraint(:company_id, name: :base_artifact_retention_events_company_positive)
    |> check_constraint(:event, name: :base_artifact_retention_events_event_check)
    |> foreign_key_constraint(:artifact_id,
      name: :base_artifact_retention_events_artifact_id_fkey
    )
    |> foreign_key_constraint(:tenant_id, name: :base_artifact_retention_events_tenant_id_fkey)
  end
end
