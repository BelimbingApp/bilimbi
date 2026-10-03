defmodule Bilimbi.Base.Workflow.LegacyCoordinationFixture do
  @moduledoc false
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  # Literal legacy-shaped DDL, independent of the migration and runtime contract.
  def create!(repo, prefix) do
    schema = SchemaVerifier.quote_identifier!(prefix)

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_transition_outbox" (
        "id" bigserial PRIMARY KEY,
        "event_key" varchar(255) NOT NULL,
        "event_type" varchar(255) NOT NULL,
        "payload" json NOT NULL,
        "attempts" integer NOT NULL DEFAULT 0,
        "available_at" timestamp(0) without time zone NOT NULL,
        "lease_token" varchar(64),
        "lease_expires_at" timestamp(0) without time zone,
        "delivered_at" timestamp(0) without time zone,
        "last_error" text,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_outbox_due_idx" ON #{schema}."base_workflow_transition_outbox" ("delivered_at", "available_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_outbox_lease_idx" ON #{schema}."base_workflow_transition_outbox" ("lease_expires_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_transition_outbox" ADD CONSTRAINT "base_workflow_transition_outbox_event_key_unique" UNIQUE ("event_key")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_transition_outbox" ADD CONSTRAINT "base_workflow_transition_outbox_lease_token_unique" UNIQUE ("lease_token")|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_process_definition_versions" (
        "id" bigserial PRIMARY KEY,
        "definition_key" varchar(255) NOT NULL,
        "definition_version" integer NOT NULL,
        "definition_fingerprint" char(64) NOT NULL,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_definition_versions" ADD CONSTRAINT "base_workflow_process_definition_version_unique" UNIQUE ("definition_key", "definition_version")|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_process_runs" (
        "id" bigserial PRIMARY KEY,
        "definition_key" varchar(255) NOT NULL,
        "definition_version" integer NOT NULL,
        "definition_fingerprint" char(64) NOT NULL,
        "status" varchar(255) NOT NULL,
        "priority" integer NOT NULL DEFAULT 0,
        "subject_type" varchar(255),
        "subject_id" varchar(255),
        "correlation_key" varchar(255),
        "input" json,
        "output" json,
        "idempotency_key" varchar(255),
        "last_error" text,
        "started_at" timestamp(0) without time zone NOT NULL,
        "available_at" timestamp(0) without time zone NOT NULL,
        "heartbeat_at" timestamp(0) without time zone,
        "paused_at" timestamp(0) without time zone,
        "pause_reason" text,
        "completed_at" timestamp(0) without time zone,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone,
        "scope_type" varchar(16) NOT NULL DEFAULT 'unresolved',
        "tenant_id" bigint
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_process_correlation_idx" ON #{schema}."base_workflow_process_runs" ("correlation_key")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_process_definition_idx" ON #{schema}."base_workflow_process_runs" ("definition_key", "definition_version")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_runs" ADD CONSTRAINT "base_workflow_process_runs_idempotency_key_unique" UNIQUE ("idempotency_key")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_process_scope_idx" ON #{schema}."base_workflow_process_runs" ("scope_type", "tenant_id")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_process_status_idx" ON #{schema}."base_workflow_process_runs" ("status", "available_at", "priority")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_process_subject_idx" ON #{schema}."base_workflow_process_runs" ("subject_type", "subject_id")|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_process_work_items" (
        "id" bigserial PRIMARY KEY,
        "process_run_id" bigint NOT NULL,
        "step_key" varchar(255) NOT NULL,
        "label" varchar(255) NOT NULL,
        "executor_key" varchar(255) NOT NULL,
        "status" varchar(255) NOT NULL,
        "dependency_mode" varchar(3) NOT NULL DEFAULT 'all',
        "required_signal" varchar(255),
        "signalled_at" timestamp(0) without time zone,
        "signal_payload" json,
        "delay_seconds" integer NOT NULL DEFAULT 0,
        "available_at" timestamp(0) without time zone,
        "attempts" integer NOT NULL DEFAULT 0,
        "max_attempts" integer NOT NULL DEFAULT 1,
        "priority" integer NOT NULL DEFAULT 0,
        "lease_owner" varchar(255),
        "lease_token" varchar(64),
        "lease_expires_at" timestamp(0) without time zone,
        "heartbeat_at" timestamp(0) without time zone,
        "outcome" varchar(255),
        "input" json,
        "input_ref" varchar(255),
        "output" json,
        "result_ref" varchar(255),
        "metadata" json,
        "last_error" text,
        "completed_at" timestamp(0) without time zone,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone,
        "tenant_id" bigint,
        "version" integer NOT NULL DEFAULT 1
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" ADD CONSTRAINT "base_workflow_process_step_unique" UNIQUE ("process_run_id", "step_key")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" ADD CONSTRAINT "base_workflow_process_work_items_lease_token_unique" UNIQUE ("lease_token")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_work_available_idx" ON #{schema}."base_workflow_process_work_items" ("status", "available_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_work_lease_idx" ON #{schema}."base_workflow_process_work_items" ("lease_expires_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_work_priority_idx" ON #{schema}."base_workflow_process_work_items" ("status", "priority", "available_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_work_tenant_status_idx" ON #{schema}."base_workflow_process_work_items" ("tenant_id", "status")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_work_items" ADD CONSTRAINT "base_workflow_process_work_items_process_run_id_foreign" FOREIGN KEY ("process_run_id") REFERENCES #{schema}."base_workflow_process_runs" ("id") ON DELETE CASCADE|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_process_dependencies" (
        "id" bigserial PRIMARY KEY,
        "work_item_id" bigint NOT NULL,
        "depends_on_work_item_id" bigint NOT NULL,
        "acceptable_outcomes" json NOT NULL,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone,
        "tenant_id" bigint
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_dependency_tenant_idx" ON #{schema}."base_workflow_process_dependencies" ("tenant_id")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" ADD CONSTRAINT "base_workflow_process_dependency_unique" UNIQUE ("work_item_id", "depends_on_work_item_id")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" ADD CONSTRAINT "base_workflow_process_dependencies_work_item_id_foreign" FOREIGN KEY ("work_item_id") REFERENCES #{schema}."base_workflow_process_work_items" ("id") ON DELETE CASCADE|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_dependencies" ADD CONSTRAINT "wf_dep_depends_fk" FOREIGN KEY ("depends_on_work_item_id") REFERENCES #{schema}."base_workflow_process_work_items" ("id") ON DELETE CASCADE|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_process_events" (
        "id" bigserial PRIMARY KEY,
        "process_run_id" bigint NOT NULL,
        "work_item_id" bigint,
        "sequence" bigint NOT NULL,
        "type" varchar(255) NOT NULL,
        "payload" json,
        "idempotency_key" varchar(255),
        "occurred_at" timestamp(0) without time zone NOT NULL,
        "created_at" timestamp(0) without time zone,
        "tenant_id" bigint
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_event_tenant_time_idx" ON #{schema}."base_workflow_process_events" ("tenant_id", "occurred_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_event_sequence_unique" UNIQUE ("process_run_id", "sequence")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_process_event_timeline_idx" ON #{schema}."base_workflow_process_events" ("process_run_id", "occurred_at")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_events_idempotency_key_unique" UNIQUE ("idempotency_key")|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_events_process_run_id_foreign" FOREIGN KEY ("process_run_id") REFERENCES #{schema}."base_workflow_process_runs" ("id") ON DELETE CASCADE|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_process_events" ADD CONSTRAINT "base_workflow_process_events_work_item_id_foreign" FOREIGN KEY ("work_item_id") REFERENCES #{schema}."base_workflow_process_work_items" ("id") ON DELETE SET NULL|,
      []
    )
  end

  # Generic saved PHP-v1 graph, including completed output and carried owner
  # facts. Values are literal source-shaped data, never runtime materialization.
  def insert_in_flight!(repo, prefix, tenant_id \\ 1, subject_id \\ 41) do
    schema = SchemaVerifier.quote_identifier!(prefix)
    fingerprint = "16228f12190a4b197eab2cf83d063af3a44bb0b6a9c41d0d6207b6c2515455ea"
    time = ~N[2026-01-01 00:00:00]
    input = %{"coordination_attempt" => 2, "carried_fact_ids" => %{"earlier" => 73}}

    SQL.query!(
      repo,
      """
      INSERT INTO #{schema}.base_workflow_process_definition_versions
        (definition_key, definition_version, definition_fingerprint, created_at, updated_at)
      VALUES ('example.parallel', 1, $1, $2, $2)
      """,
      [fingerprint, time]
    )

    [[run_id]] =
      SQL.query!(
        repo,
        """
        INSERT INTO #{schema}.base_workflow_process_runs
          (definition_key, definition_version, definition_fingerprint, status,
           subject_type, subject_id, correlation_key, input, idempotency_key,
           started_at, available_at, heartbeat_at, created_at, updated_at, scope_type, tenant_id)
        VALUES ('example.parallel', 1, $1, 'running', $2, $3, 'owner-round:2', $4,
          $5, $6, $6, $6, $6, $6, 'tenant', $7) RETURNING id
        """,
        [
          fingerprint,
          "Legacy\\Example\\Record",
          to_string(subject_id),
          input,
          "start:tenant:#{tenant_id}:example.parallel:retained-attempt",
          time,
          tenant_id
        ]
      ).rows

    items =
      for key <- ~w(first second third) do
        status = if key == "first", do: "completed", else: "available"
        output = if key == "first", do: %{"saved_fact" => 74}
        version = if key == "first", do: 2, else: 1
        outcome = if key == "first", do: "completed"
        result_ref = if key == "first", do: "owner-result:74"
        completed_at = if key == "first", do: time

        [[id]] =
          SQL.query!(
            repo,
            """
            INSERT INTO #{schema}.base_workflow_process_work_items
              (process_run_id, step_key, label, executor_key, status, available_at,
               input, metadata, output, outcome, result_ref, completed_at, version,
               tenant_id, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, '[]', $7, $8, $9, $10, $11, $12, $13, $6, $6)
            RETURNING id
            """,
            [
              run_id,
              key,
              String.capitalize(key),
              "example." <> key,
              status,
              time,
              %{"lane" => key},
              output,
              outcome,
              result_ref,
              completed_at,
              version,
              tenant_id
            ]
          ).rows

        {key, id}
      end

    SQL.query!(
      repo,
      """
      INSERT INTO #{schema}.base_workflow_process_events
        (process_run_id, sequence, type, payload, occurred_at, created_at, tenant_id)
      VALUES ($1, 1, 'process.started', $2, $3, $3, $4)
      """,
      [
        run_id,
        %{"subject_type" => "Legacy\\Example\\Record", "subject_id" => to_string(subject_id)},
        time,
        tenant_id
      ]
    )

    SQL.query!(
      repo,
      """
      INSERT INTO #{schema}.base_workflow_process_events
        (process_run_id, work_item_id, sequence, type, payload, occurred_at, created_at, tenant_id)
      VALUES ($1, $2, 2, 'work.completed', $3, $4, $4, $5)
      """,
      [
        run_id,
        Map.new(items)["first"],
        %{
          "outcome" => "completed",
          "output" => %{"saved_fact" => 74},
          "result_ref" => "owner-result:74"
        },
        time,
        tenant_id
      ]
    )

    %{run_id: run_id, items: Map.new(items), input: input, fingerprint: fingerprint}
  end
end
