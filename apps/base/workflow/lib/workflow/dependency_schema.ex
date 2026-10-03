defmodule Bilimbi.Base.Workflow.DependencySchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_process_dependencies" do
    field(:work_item_id, :integer)
    field(:depends_on_work_item_id, :integer)
    field(:acceptable_outcomes, Bilimbi.Base.Workflow.JSON)
    field(:created_at, :naive_datetime)
    field(:updated_at, :naive_datetime)
    field(:tenant_id, :integer)
  end
end
