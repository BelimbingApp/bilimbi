defmodule Bilimbi.Base.Workflow.HistorySchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_workflow_status_history" do
    field :flow, :string
    field :flow_id, :id
    field :status, :string
    field :tat, :integer
    field :actor_id, :id
    field :actor_role, :string
    field :actor_department, :string
    field :actor_company, :string
    field :assignees, Bilimbi.Base.Workflow.JSON
    field :comment, :string
    field :comment_tag, :string
    field :attachments, Bilimbi.Base.Workflow.JSON
    field :metadata, Bilimbi.Base.Workflow.JSON
    field :transitioned_at, :naive_datetime
    field :created_at, :naive_datetime
    field :actor_type, :string
  end
end
