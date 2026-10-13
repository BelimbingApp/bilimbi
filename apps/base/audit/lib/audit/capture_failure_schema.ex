defmodule Bilimbi.Base.Audit.CaptureFailureSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_audit_capture_failures" do
    field :action, :string
    field :schema_name, :string
    field :error_type, :string
    field :actor_type, :string
    field :actor_id, :id
    field :impersonator_id, :id
    field :system_principal, :string
    field :company_id, :id
    field :tenant_id, :id
    field :trace_id, :string
    field :recorded_at, :naive_datetime_usec, read_after_writes: true
  end
end
