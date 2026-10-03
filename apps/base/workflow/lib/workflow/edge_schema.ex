defmodule Bilimbi.Base.Workflow.EdgeSchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_workflow_status_transitions" do
    field :flow, :string
    field :from_code, :string
    field :to_code, :string
    field :label, :string
    field :capability, :string
    field :guard_class, :string
    field :action_class, :string
    field :sla_seconds, :integer
    field :metadata, Bilimbi.Base.Workflow.JSON
    field :position, :integer
    field :is_active, :boolean
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end
end
