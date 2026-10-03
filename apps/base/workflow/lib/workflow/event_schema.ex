defmodule Bilimbi.Base.Workflow.EventSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_process_events" do
    field(:process_run_id, :integer)
    field(:work_item_id, :integer)
    field(:sequence, :integer)
    field(:type, :string)
    field(:payload, Bilimbi.Base.Workflow.JSON)
    field(:idempotency_key, :string)
    field(:occurred_at, :naive_datetime)
    field(:created_at, :naive_datetime)
    field(:tenant_id, :integer)
  end
end
