defmodule Bilimbi.Base.Workflow.RunSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_process_runs" do
    field(:definition_key, :string)
    field(:definition_version, :integer)
    field(:definition_fingerprint, :string)
    field(:status, :string)
    field(:priority, :integer, default: 0)
    field(:subject_type, :string)
    field(:subject_id, :string)
    field(:correlation_key, :string)
    field(:input, Bilimbi.Base.Workflow.JSON)
    field(:output, Bilimbi.Base.Workflow.JSON)
    field(:idempotency_key, :string)
    field(:last_error, :string)
    field(:started_at, :naive_datetime)
    field(:available_at, :naive_datetime)
    field(:heartbeat_at, :naive_datetime)
    field(:paused_at, :naive_datetime)
    field(:pause_reason, :string)
    field(:completed_at, :naive_datetime)
    field(:created_at, :naive_datetime)
    field(:updated_at, :naive_datetime)
    field(:scope_type, :string, default: "unresolved")
    field(:tenant_id, :integer)
  end
end
