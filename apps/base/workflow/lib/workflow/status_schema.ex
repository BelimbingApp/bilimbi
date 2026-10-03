defmodule Bilimbi.Base.Workflow.StatusSchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_workflow_status_configs" do
    field :flow, :string
    field :code, :string
    field :label, :string
    field :pic, Bilimbi.Base.Workflow.JSON
    field :notifications, Bilimbi.Base.Workflow.JSON
    field :position, :integer
    field :comment_tags, Bilimbi.Base.Workflow.JSON
    field :prompt, :string
    field :kanban_code, :string
    field :is_active, :boolean
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end
end
