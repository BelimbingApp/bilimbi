defmodule Bilimbi.Base.Workflow.WorkSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_process_work_items" do
    field(:process_run_id, :integer)
    field(:step_key, :string)
    field(:label, :string)
    field(:executor_key, :string)
    field(:status, :string)
    field(:dependency_mode, :string, default: "all")
    field(:required_signal, :string)
    field(:signalled_at, :naive_datetime)
    field(:signal_payload, Bilimbi.Base.Workflow.JSON)
    field(:delay_seconds, :integer, default: 0)
    field(:available_at, :naive_datetime)
    field(:attempts, :integer, default: 0)
    field(:max_attempts, :integer, default: 1)
    field(:priority, :integer, default: 0)
    field(:lease_owner, :string)
    field(:lease_token, :string)
    field(:lease_expires_at, :naive_datetime)
    field(:heartbeat_at, :naive_datetime)
    field(:outcome, :string)
    field(:input, Bilimbi.Base.Workflow.JSON)
    field(:input_ref, :string)
    field(:output, Bilimbi.Base.Workflow.JSON)
    field(:result_ref, :string)
    field(:metadata, Bilimbi.Base.Workflow.JSON)
    field(:last_error, :string)
    field(:completed_at, :naive_datetime)
    field(:created_at, :naive_datetime)
    field(:updated_at, :naive_datetime)
    field(:tenant_id, :integer)
    field(:version, :integer, default: 1)
  end
end
