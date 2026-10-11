defmodule Bilimbi.Base.Integration.SchemaContract do
  @moduledoc "Belimbing exchange baseline with optional Bilimbi general-log columns."
  @behaviour Bilimbi.Base.Database.SchemaContract
  def migration_version, do: 20_261_011_100_000
  @impl true
  def tables do
    [
      %{
        name: "base_integration_outbound_exchanges",
        columns: %{
          "id" => column({:varchar, 40}, false, nil),
          "system" => column({:varchar, 255}, false, nil),
          "provider" => column({:varchar, 255}, true, nil),
          "operation" => column({:varchar, 255}, false, nil),
          "transport" => column({:varchar, 40}, false, {:string, "http"}),
          "protocol" => column({:varchar, 40}, false, {:string, "rest"}),
          "protocol_operation" => column({:varchar, 255}, true, nil),
          "endpoint" => column(:text, false, nil),
          "owner_type" => column({:varchar, 255}, true, nil),
          "owner_id" => column(:bigint, true, nil),
          "correlation_id" => column({:varchar, 255}, true, nil),
          "traceparent" => column({:varchar, 255}, true, nil),
          "tracestate" => column(:text, true, nil),
          "request_headers" => column(:json, true, nil),
          "request_body" => column(:json, true, nil),
          "request_body_truncated" => column(:boolean, false, {:boolean, false}),
          "request_body_original_bytes" => column(:integer, true, nil),
          "response_status" => column(:smallint, true, nil),
          "response_headers" => column(:json, true, nil),
          "response_body" => column(:json, true, nil),
          "response_body_truncated" => column(:boolean, false, {:boolean, false}),
          "response_body_original_bytes" => column(:integer, true, nil),
          "duration_ms" => column(:integer, true, nil),
          "retry_count" => column(:smallint, false, {:integer, 0}),
          "outcome" => column({:varchar, 40}, false, nil),
          "error_class" => column({:varchar, 255}, true, nil),
          "error_message" => column(:text, true, nil),
          "fallback_used" => column(:boolean, false, {:boolean, false}),
          "fallback_reason" => column({:varchar, 255}, true, nil),
          "metadata" => column(:json, true, nil),
          "occurred_at" => column({:timestamp, 0}, false, nil),
          "created_at" => column({:timestamp, 0}, true, nil),
          "updated_at" => column({:timestamp, 0}, true, nil),
          "tenant_id" => column(:bigint, true, nil)
        },
        optional_columns: %{
          "direction" => column({:varchar, 10}, false, {:string, "outgoing"}),
          "method" => column({:varchar, 16}),
          "host" => column({:varchar, 255}),
          "path" => column(:text),
          "person_id" => column(:bigint),
          "impersonator_id" => column(:bigint),
          "connection_id" => column({:varchar, 255}),
          "agent_id" => column({:varchar, 255}),
          "run_id" => column({:varchar, 255})
        },
        indexes: %{
          "base_integration_outbound_exchanges_pkey" => index(["id"], true),
          "base_integration_outbound_exchanges_correlation_id_index" => index(["correlation_id"]),
          "base_integration_outbound_exchanges_occurred_at_index" => index(["occurred_at"]),
          "base_integration_outbound_exchanges_operation_index" => index(["operation"]),
          "base_integration_outbound_exchanges_outcome_index" => index(["outcome"]),
          "base_integration_outbound_exchanges_owner_type_owner_id_index" =>
            index(["owner_type", "owner_id"]),
          "base_integration_outbound_exchanges_protocol_index" => index(["protocol"]),
          "base_integration_outbound_exchanges_protocol_operation_index" =>
            index(["protocol_operation"]),
          "base_integration_outbound_exchanges_provider_index" => index(["provider"]),
          "base_integration_outbound_exchanges_response_status_index" =>
            index(["response_status"]),
          "base_integration_outbound_exchanges_system_index" => index(["system"]),
          "base_integration_outbound_exchanges_system_occurred_at_index" =>
            index(["system", "occurred_at"]),
          "base_integration_outbound_exchanges_system_operation_index" =>
            index(["system", "operation"]),
          "base_integration_outbound_exchanges_tenant_id_index" => index(["tenant_id"]),
          "base_integration_outbound_exchanges_transport_index" => index(["transport"]),
          "base_integration_outbound_exchanges_transport_protocol_index" =>
            index(["transport", "protocol"])
        },
        optional_indexes: %{
          "integration_exchange_timeline" =>
            index(["tenant_id", "direction", "occurred_at", "id"])
        },
        optional_checks: %{
          "integration_exchange_direction" => %{
            expression: "direction::text = 'incoming'::text OR direction::text = 'outgoing'::text"
          }
        },
        optional_groups: [
          %{
            name: "general API exchange log",
            columns:
              ~w(direction method host path person_id impersonator_id connection_id agent_id run_id),
            indexes: ["integration_exchange_timeline"],
            checks: ["integration_exchange_direction"]
          }
        ],
        foreign_keys: %{}
      }
    ]
  end

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}
end
