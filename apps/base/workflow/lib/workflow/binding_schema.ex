defmodule Bilimbi.Base.Workflow.BindingSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_subject_bindings" do
    field :tenant_id, :id
    field :flow, :string
    field :flow_id, :id
    field :subject_type, :string
    field :subject_id, :string
    field :owner, :string
    field :created_at, :naive_datetime
  end
end
