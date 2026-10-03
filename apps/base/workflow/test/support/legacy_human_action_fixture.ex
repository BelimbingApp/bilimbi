defmodule Bilimbi.Base.Workflow.LegacyHumanActionFixture do
  @moduledoc false
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  # Literal legacy-shaped DDL, independent of the migration and runtime contract.
  def create!(repo, prefix) do
    schema = SchemaVerifier.quote_identifier!(prefix)

    SQL.query!(
      repo,
      """
      CREATE TABLE #{schema}."base_workflow_human_action_requests" (
        "id" bigserial PRIMARY KEY,
        "tenant_id" bigint NOT NULL,
        "idempotency_key" varchar(255) NOT NULL,
        "intent_hash" char(64) NOT NULL,
        "action_key" varchar(255) NOT NULL,
        "subject_type" varchar(255) NOT NULL,
        "subject_id" varchar(255) NOT NULL,
        "process_run_id" bigint,
        "work_item_id" bigint,
        "actor_type" varchar(255) NOT NULL,
        "actor_id" bigint NOT NULL,
        "result" json,
        "completed_at" timestamp(0) without time zone,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{schema}."base_workflow_human_action_requests" ADD CONSTRAINT "base_workflow_human_request_unique" UNIQUE ("tenant_id", "idempotency_key")|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_human_subject_idx" ON #{schema}."base_workflow_human_action_requests" ("tenant_id", "subject_type", "subject_id")|,
      []
    )
  end

  # A source request row as Belimbing saved it: the PHP subject class, the
  # digest it computed, and its result JSON in the source shape. Pass
  # `result: nil, completed_at: nil` for a request the source never finished.
  def insert_request!(repo, prefix, attrs) do
    schema = SchemaVerifier.quote_identifier!(prefix)
    time = ~N[2026-01-01 00:00:00]

    attrs =
      Map.merge(
        %{
          tenant_id: 1,
          subject_type: "Legacy\\Example\\Record",
          subject_id: "41",
          process_run_id: nil,
          work_item_id: nil,
          actor_type: "user",
          actor_id: 7,
          output: %{},
          result_ref: nil,
          completed_at: time
        },
        attrs
      )

    result =
      Map.get_lazy(attrs, :result, fn ->
        %{
          "action_key" => attrs.action_key,
          "output" => attrs.output,
          "outcome" => "completed",
          "result_ref" => attrs.result_ref,
          "work_item_id" => attrs.work_item_id
        }
      end)

    [[id]] =
      SQL.query!(
        repo,
        """
        INSERT INTO #{schema}."base_workflow_human_action_requests"
          (tenant_id, idempotency_key, intent_hash, action_key, subject_type, subject_id,
           process_run_id, work_item_id, actor_type, actor_id, result, completed_at,
           created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $13) RETURNING id
        """,
        [
          attrs.tenant_id,
          attrs.idempotency_key,
          attrs.intent_hash,
          attrs.action_key,
          attrs.subject_type,
          attrs.subject_id,
          attrs.process_run_id,
          attrs.work_item_id,
          attrs.actor_type,
          attrs.actor_id,
          result,
          attrs.completed_at,
          time
        ]
      ).rows

    id
  end
end
