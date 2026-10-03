defmodule Bilimbi.Base.Workflow.KanbanSchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_workflow_kanban_columns" do
    field :flow, :string
    field :code, :string
    field :label, :string
    field :position, :integer
    field :wip_limit, :integer
    field :settings, Bilimbi.Base.Workflow.JSON
    field :description, :string
    field :is_active, :boolean
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end
end
