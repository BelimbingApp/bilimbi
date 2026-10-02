defmodule Bilimbi.Base.Workflow.FlowSchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "base_workflow" do
    field :code, :string
    field :label, :string
    field :module, :string
    field :description, :string
    field :model_class, :string
    field :settings, Bilimbi.Base.Workflow.JSON
    field :is_active, :boolean
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end
end
