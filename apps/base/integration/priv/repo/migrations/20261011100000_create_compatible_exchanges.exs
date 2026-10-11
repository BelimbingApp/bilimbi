defmodule Bilimbi.Base.Integration.Migrations.CreateCompatibleExchanges do
  use Ecto.Migration

  def change do
    # Belimbing migrations 0100_01_19_000001 and 000004; JSON stays JSON,
    # timestamps stay second precision, and legacy tenant ownership stays null.
    create table(:base_integration_outbound_exchanges, primary_key: false) do
      add :id, :string, size: 40, null: false, primary_key: true
      add :system, :string, size: 255, null: false
      add :provider, :string, size: 255
      add :operation, :string, size: 255, null: false
      add :transport, :string, size: 40, null: false, default: "http"
      add :protocol, :string, size: 40, null: false, default: "rest"
      add :protocol_operation, :string, size: 255
      add :endpoint, :text, null: false
      add :owner_type, :string, size: 255
      add :owner_id, :bigint
      add :correlation_id, :string, size: 255
      add :traceparent, :string, size: 255
      add :tracestate, :text
      add :request_headers, :json
      add :request_body, :json
      add :request_body_truncated, :boolean, null: false, default: false
      add :request_body_original_bytes, :integer
      add :response_status, :smallint
      add :response_headers, :json
      add :response_body, :json
      add :response_body_truncated, :boolean, null: false, default: false
      add :response_body_original_bytes, :integer
      add :duration_ms, :integer
      add :retry_count, :smallint, null: false, default: 0
      add :outcome, :string, size: 40, null: false
      add :error_class, :string, size: 255
      add :error_message, :text
      add :fallback_used, :boolean, null: false, default: false
      add :fallback_reason, :string, size: 255
      add :metadata, :json
      add :occurred_at, :naive_datetime, null: false
      add :created_at, :naive_datetime
      add :updated_at, :naive_datetime
      add :tenant_id, :bigint
    end

    create index(:base_integration_outbound_exchanges, [:correlation_id],
             name: :base_integration_outbound_exchanges_correlation_id_index
           )

    create index(:base_integration_outbound_exchanges, [:occurred_at],
             name: :base_integration_outbound_exchanges_occurred_at_index
           )

    create index(:base_integration_outbound_exchanges, [:operation],
             name: :base_integration_outbound_exchanges_operation_index
           )

    create index(:base_integration_outbound_exchanges, [:outcome],
             name: :base_integration_outbound_exchanges_outcome_index
           )

    create index(:base_integration_outbound_exchanges, [:owner_type, :owner_id],
             name: :base_integration_outbound_exchanges_owner_type_owner_id_index
           )

    create index(:base_integration_outbound_exchanges, [:protocol],
             name: :base_integration_outbound_exchanges_protocol_index
           )

    create index(:base_integration_outbound_exchanges, [:protocol_operation],
             name: :base_integration_outbound_exchanges_protocol_operation_index
           )

    create index(:base_integration_outbound_exchanges, [:provider],
             name: :base_integration_outbound_exchanges_provider_index
           )

    create index(:base_integration_outbound_exchanges, [:response_status],
             name: :base_integration_outbound_exchanges_response_status_index
           )

    create index(:base_integration_outbound_exchanges, [:system],
             name: :base_integration_outbound_exchanges_system_index
           )

    create index(:base_integration_outbound_exchanges, [:system, :occurred_at],
             name: :base_integration_outbound_exchanges_system_occurred_at_index
           )

    create index(:base_integration_outbound_exchanges, [:system, :operation],
             name: :base_integration_outbound_exchanges_system_operation_index
           )

    create index(:base_integration_outbound_exchanges, [:tenant_id],
             name: :base_integration_outbound_exchanges_tenant_id_index
           )

    create index(:base_integration_outbound_exchanges, [:transport],
             name: :base_integration_outbound_exchanges_transport_index
           )

    create index(:base_integration_outbound_exchanges, [:transport, :protocol],
             name: :base_integration_outbound_exchanges_transport_protocol_index
           )
  end
end
