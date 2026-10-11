defmodule Bilimbi.Base.Integration.Exchange do
  @moduledoc false
  use Ecto.Schema
  # Keep the source morph identity and payload protection during manual deletion.
  def __audit_auditable_type__, do: "App\\Base\\Integration\\Models\\OutboundExchange"

  def __audit_redacted_fields__,
    do:
      ~w(request_headers request_body response_headers response_body metadata traceparent tracestate endpoint error_message)a

  @primary_key {:id, :string, autogenerate: false}
  schema "base_integration_outbound_exchanges" do
    field :system, :string
    field :provider, :string
    field :operation, :string
    field :transport, :string
    field :protocol, :string
    field :protocol_operation, :string
    field :endpoint, :string
    field :owner_type, :string
    field :owner_id, :integer
    field :correlation_id, :string
    field :traceparent, :string
    field :tracestate, :string
    field :request_headers, :map
    field :request_body, :map
    field :request_body_truncated, :boolean
    field :request_body_original_bytes, :integer
    field :response_status, :integer
    field :response_headers, :map
    field :response_body, :map
    field :response_body_truncated, :boolean
    field :response_body_original_bytes, :integer
    field :duration_ms, :integer
    field :retry_count, :integer
    field :outcome, :string
    field :error_class, :string
    field :error_message, :string
    field :fallback_used, :boolean
    field :fallback_reason, :string
    field :metadata, :map
    field :occurred_at, :naive_datetime
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
    field :tenant_id, :integer
    field :direction, :string, default: "outgoing"
    field :method, :string
    field :host, :string
    field :path, :string
    field :person_id, :integer
    field :impersonator_id, :integer
    field :connection_id, :string
    field :agent_id, :string
    field :run_id, :string
  end
end
