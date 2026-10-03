defmodule Bilimbi.Base.Workflow.RequestSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_human_action_requests" do
    field(:tenant_id, :integer)
    field(:idempotency_key, :string)
    field(:intent_hash, :string)
    field(:action_key, :string)
    field(:subject_type, :string)
    field(:subject_id, :string)
    field(:process_run_id, :integer)
    field(:work_item_id, :integer)
    field(:actor_type, :string)
    field(:actor_id, :integer)
    field(:result, Bilimbi.Base.Workflow.JSON)
    field(:completed_at, :naive_datetime)
    field(:created_at, :naive_datetime)
    field(:updated_at, :naive_datetime)
  end
end
