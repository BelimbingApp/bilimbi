defmodule Bilimbi.Base.Workflow.Migrations.CreateCoordinationCompatibilityBaseline do
  use Ecto.Migration

  def change do
    schema = Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(prefix() || "public")

    create table(:base_workflow_transition_outbox, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:event_key, :string, null: false)
      add(:event_type, :string, null: false)
      add(:payload, :json, null: false)
      add(:attempts, :integer, null: false, default: 0)
      add(:available_at, :naive_datetime, precision: 0, null: false)
      add(:lease_token, :string, size: 64)
      add(:lease_expires_at, :naive_datetime, precision: 0)
      add(:delivered_at, :naive_datetime, precision: 0)
      add(:last_error, :text)
      add(:created_at, :naive_datetime, precision: 0)
      add(:updated_at, :naive_datetime, precision: 0)
    end

    create(
      index(:base_workflow_transition_outbox, [:delivered_at, :available_at],
        name: :base_workflow_outbox_due_idx
      )
    )

    create(
      index(:base_workflow_transition_outbox, [:lease_expires_at],
        name: :base_workflow_outbox_lease_idx
      )
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_transition_outbox" ADD CONSTRAINT "base_workflow_transition_outbox_event_key_unique" UNIQUE ("event_key")|,
      ~s|ALTER TABLE #{schema}."base_workflow_transition_outbox" DROP CONSTRAINT "base_workflow_transition_outbox_event_key_unique"|
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_transition_outbox" ADD CONSTRAINT "base_workflow_transition_outbox_lease_token_unique" UNIQUE ("lease_token")|,
      ~s|ALTER TABLE #{schema}."base_workflow_transition_outbox" DROP CONSTRAINT "base_workflow_transition_outbox_lease_token_unique"|
    )

    create table(:base_workflow_process_definition_versions, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:definition_key, :string, null: false)
      add(:definition_version, :integer, null: false)
      add(:definition_fingerprint, :char, size: 64, null: false)
      add(:created_at, :naive_datetime, precision: 0)
      add(:updated_at, :naive_datetime, precision: 0)
    end

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_definition_versions" ADD CONSTRAINT "base_workflow_process_definition_version_unique" UNIQUE ("definition_key", "definition_version")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_definition_versions" DROP CONSTRAINT "base_workflow_process_definition_version_unique"|
    )

    create table(:base_workflow_process_runs, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:definition_key, :string, null: false)
      add(:definition_version, :integer, null: false)
      add(:definition_fingerprint, :char, size: 64, null: false)
      add(:status, :string, null: false)
      add(:priority, :integer, null: false, default: 0)
      add(:subject_type, :string)
      add(:subject_id, :string)
      add(:correlation_key, :string)
      add(:input, :json)
      add(:output, :json)
      add(:idempotency_key, :string)
      add(:last_error, :text)
      add(:started_at, :naive_datetime, precision: 0, null: false)
      add(:available_at, :naive_datetime, precision: 0, null: false)
      add(:heartbeat_at, :naive_datetime, precision: 0)
      add(:paused_at, :naive_datetime, precision: 0)
      add(:pause_reason, :text)
      add(:completed_at, :naive_datetime, precision: 0)
      add(:created_at, :naive_datetime, precision: 0)
      add(:updated_at, :naive_datetime, precision: 0)
      add(:scope_type, :string, size: 16, null: false, default: "unresolved")
      add(:tenant_id, :bigint)
    end

    create(
      index(:base_workflow_process_runs, [:correlation_key],
        name: :base_workflow_process_correlation_idx
      )
    )

    create(
      index(:base_workflow_process_runs, [:definition_key, :definition_version],
        name: :base_workflow_process_definition_idx
      )
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_runs" ADD CONSTRAINT "base_workflow_process_runs_idempotency_key_unique" UNIQUE ("idempotency_key")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_runs" DROP CONSTRAINT "base_workflow_process_runs_idempotency_key_unique"|
    )

    create(
      index(:base_workflow_process_runs, [:scope_type, :tenant_id],
        name: :base_workflow_process_scope_idx
      )
    )

    create(
      index(:base_workflow_process_runs, [:status, :available_at, :priority],
        name: :base_workflow_process_status_idx
      )
    )

    create(
      index(:base_workflow_process_runs, [:subject_type, :subject_id],
        name: :base_workflow_process_subject_idx
      )
    )

    create table(:base_workflow_process_work_items, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:process_run_id, :bigint, null: false)
      add(:step_key, :string, null: false)
      add(:label, :string, null: false)
      add(:executor_key, :string, null: false)
      add(:status, :string, null: false)
      add(:dependency_mode, :string, size: 3, null: false, default: "all")
      add(:required_signal, :string)
      add(:signalled_at, :naive_datetime, precision: 0)
      add(:signal_payload, :json)
      add(:delay_seconds, :integer, null: false, default: 0)
      add(:available_at, :naive_datetime, precision: 0)
      add(:attempts, :integer, null: false, default: 0)
      add(:max_attempts, :integer, null: false, default: 1)
      add(:priority, :integer, null: false, default: 0)
      add(:lease_owner, :string)
      add(:lease_token, :string, size: 64)
      add(:lease_expires_at, :naive_datetime, precision: 0)
      add(:heartbeat_at, :naive_datetime, precision: 0)
      add(:outcome, :string)
      add(:input, :json)
      add(:input_ref, :string)
      add(:output, :json)
      add(:result_ref, :string)
      add(:metadata, :json)
      add(:last_error, :text)
      add(:completed_at, :naive_datetime, precision: 0)
      add(:created_at, :naive_datetime, precision: 0)
      add(:updated_at, :naive_datetime, precision: 0)
      add(:tenant_id, :bigint)
      add(:version, :integer, null: false, default: 1)
    end

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" ADD CONSTRAINT "base_workflow_process_step_unique" UNIQUE ("process_run_id", "step_key")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" DROP CONSTRAINT "base_workflow_process_step_unique"|
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" ADD CONSTRAINT "base_workflow_process_work_items_lease_token_unique" UNIQUE ("lease_token")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" DROP CONSTRAINT "base_workflow_process_work_items_lease_token_unique"|
    )

    create(
      index(:base_workflow_process_work_items, [:status, :available_at],
        name: :base_workflow_work_available_idx
      )
    )

    create(
      index(:base_workflow_process_work_items, [:lease_expires_at],
        name: :base_workflow_work_lease_idx
      )
    )

    create(
      index(:base_workflow_process_work_items, [:status, :priority, :available_at],
        name: :base_workflow_work_priority_idx
      )
    )

    create(
      index(:base_workflow_process_work_items, [:tenant_id, :status],
        name: :base_workflow_work_tenant_status_idx
      )
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" ADD CONSTRAINT "base_workflow_process_work_items_process_run_id_foreign" FOREIGN KEY ("process_run_id") REFERENCES #{schema}."base_workflow_process_runs" ("id") ON DELETE CASCADE|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" DROP CONSTRAINT "base_workflow_process_work_items_process_run_id_foreign"|
    )

    create table(:base_workflow_process_dependencies, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:work_item_id, :bigint, null: false)
      add(:depends_on_work_item_id, :bigint, null: false)
      add(:acceptable_outcomes, :json, null: false)
      add(:created_at, :naive_datetime, precision: 0)
      add(:updated_at, :naive_datetime, precision: 0)
      add(:tenant_id, :bigint)
    end

    create(
      index(:base_workflow_process_dependencies, [:tenant_id],
        name: :base_workflow_dependency_tenant_idx
      )
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" ADD CONSTRAINT "base_workflow_process_dependency_unique" UNIQUE ("work_item_id", "depends_on_work_item_id")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" DROP CONSTRAINT "base_workflow_process_dependency_unique"|
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" ADD CONSTRAINT "base_workflow_process_dependencies_work_item_id_foreign" FOREIGN KEY ("work_item_id") REFERENCES #{schema}."base_workflow_process_work_items" ("id") ON DELETE CASCADE|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" DROP CONSTRAINT "base_workflow_process_dependencies_work_item_id_foreign"|
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" ADD CONSTRAINT "wf_dep_depends_fk" FOREIGN KEY ("depends_on_work_item_id") REFERENCES #{schema}."base_workflow_process_work_items" ("id") ON DELETE CASCADE|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" DROP CONSTRAINT "wf_dep_depends_fk"|
    )

    create table(:base_workflow_process_events, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:process_run_id, :bigint, null: false)
      add(:work_item_id, :bigint)
      add(:sequence, :bigint, null: false)
      add(:type, :string, null: false)
      add(:payload, :json)
      add(:idempotency_key, :string)
      add(:occurred_at, :naive_datetime, precision: 0, null: false)
      add(:created_at, :naive_datetime, precision: 0)
      add(:tenant_id, :bigint)
    end

    create(
      index(:base_workflow_process_events, [:tenant_id, :occurred_at],
        name: :base_workflow_event_tenant_time_idx
      )
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_event_sequence_unique" UNIQUE ("process_run_id", "sequence")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" DROP CONSTRAINT "base_workflow_process_event_sequence_unique"|
    )

    create(
      index(:base_workflow_process_events, [:process_run_id, :occurred_at],
        name: :base_workflow_process_event_timeline_idx
      )
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_events_idempotency_key_unique" UNIQUE ("idempotency_key")|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" DROP CONSTRAINT "base_workflow_process_events_idempotency_key_unique"|
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_events_process_run_id_foreign" FOREIGN KEY ("process_run_id") REFERENCES #{schema}."base_workflow_process_runs" ("id") ON DELETE CASCADE|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" DROP CONSTRAINT "base_workflow_process_events_process_run_id_foreign"|
    )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_events_work_item_id_foreign" FOREIGN KEY ("work_item_id") REFERENCES #{schema}."base_workflow_process_work_items" ("id") ON DELETE SET NULL|,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" DROP CONSTRAINT "base_workflow_process_events_work_item_id_foreign"|
    )
  end
end
