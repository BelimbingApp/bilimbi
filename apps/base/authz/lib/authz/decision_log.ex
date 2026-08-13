defmodule Bilimbi.Base.Authz.DecisionLog do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "base_authz_decision_logs" do
    field :company_id, :id
    field :actor_type, :string
    field :actor_id, :id
    field :acting_for_user_id, :id
    field :capability, :string
    field :resource_type, :string
    field :resource_id, :string
    field :allowed, :boolean
    field :reason_code, :string
    field :applied_policies, Bilimbi.Base.Database.Json
    field :context, Bilimbi.Base.Database.Json
    field :trace_id, :string
    field :occurred_at, :naive_datetime
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attributes) do
    %__MODULE__{}
    |> cast(attributes, [
      :company_id,
      :actor_type,
      :actor_id,
      :acting_for_user_id,
      :capability,
      :resource_type,
      :resource_id,
      :allowed,
      :reason_code,
      :applied_policies,
      :context,
      :trace_id,
      :occurred_at
    ])
    |> validate_required([
      :actor_type,
      :actor_id,
      :capability,
      :allowed,
      :reason_code,
      :occurred_at
    ])
    |> validate_length(:actor_type, max: 40)
    |> validate_length(:capability, max: 255)
    |> validate_length(:resource_type, max: 255)
    |> validate_length(:resource_id, max: 255)
    |> validate_length(:reason_code, max: 255)
    |> validate_length(:trace_id, max: 12)
  end
end
