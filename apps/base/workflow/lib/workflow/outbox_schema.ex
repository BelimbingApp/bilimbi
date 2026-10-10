defmodule Bilimbi.Base.Workflow.OutboxSchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_workflow_transition_outbox" do
    field :event_key, :string
    field :event_type, :string
    field :payload, Bilimbi.Base.Workflow.JSON
    field :attempts, :integer, default: 0
    field :available_at, :naive_datetime
    field :lease_token, :string
    field :lease_expires_at, :naive_datetime
    field :delivered_at, :naive_datetime
    field :last_error, :string
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end
end
