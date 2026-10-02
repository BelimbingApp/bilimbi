defmodule Bilimbi.Base.Workflow.LegacyStatusFixture do
  @moduledoc false
  alias Ecto.Adapters.SQL
  alias Bilimbi.Base.Database.SchemaVerifier

  def create!(repo, prefix) do
    quoted = SchemaVerifier.quote_identifier!(prefix)

    SQL.query!(
      repo,
      """
      CREATE TABLE #{quoted}."base_workflow" (
        id bigserial PRIMARY KEY,
        "code" character varying(255) NOT NULL,
        "label" character varying(255) NOT NULL,
        "module" character varying(255),
        "description" text,
        "model_class" character varying(255),
        "settings" json,
        "is_active" boolean NOT NULL DEFAULT true,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{quoted}."base_workflow" ADD CONSTRAINT "base_workflow_code_unique" UNIQUE (code)|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{quoted}."base_workflow_status_configs" (
        id bigserial PRIMARY KEY,
        "flow" character varying(255) NOT NULL,
        "code" character varying(255) NOT NULL,
        "label" character varying(255) NOT NULL,
        "pic" json,
        "notifications" json,
        "position" integer NOT NULL DEFAULT 0,
        "comment_tags" json,
        "prompt" text,
        "kanban_code" character varying(255),
        "is_active" boolean NOT NULL DEFAULT true,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{quoted}."base_workflow_status_configs" ADD CONSTRAINT "base_workflow_status_configs_flow_code_unique" UNIQUE (flow, code)|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_status_configs_flow_index" ON #{quoted}."base_workflow_status_configs" (flow)|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_status_configs_flow_is_active_position_index" ON #{quoted}."base_workflow_status_configs" (flow, is_active, "position")|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{quoted}."base_workflow_status_transitions" (
        id bigserial PRIMARY KEY,
        "flow" character varying(255) NOT NULL,
        "from_code" character varying(255) NOT NULL,
        "to_code" character varying(255) NOT NULL,
        "label" character varying(255),
        "capability" character varying(255),
        "guard_class" character varying(255),
        "action_class" character varying(255),
        "sla_seconds" integer,
        "metadata" json,
        "position" integer NOT NULL DEFAULT 0,
        "is_active" boolean NOT NULL DEFAULT true,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_status_transitions_flow_from_code_is_active_index" ON #{quoted}."base_workflow_status_transitions" (flow, from_code, is_active)|,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{quoted}."base_workflow_status_transitions" ADD CONSTRAINT "base_workflow_status_transitions_flow_from_code_to_code_unique" UNIQUE (flow, from_code, to_code)|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{quoted}."base_workflow_status_history" (
        id bigserial PRIMARY KEY,
        "flow" character varying(255) NOT NULL,
        "flow_id" bigint NOT NULL,
        "status" character varying(255) NOT NULL,
        "tat" integer,
        "actor_id" bigint,
        "actor_role" character varying(255),
        "actor_department" character varying(255),
        "actor_company" character varying(255),
        "assignees" json,
        "comment" text,
        "comment_tag" character varying(255),
        "attachments" json,
        "metadata" json,
        "transitioned_at" timestamp(0) without time zone NOT NULL,
        "created_at" timestamp(0) without time zone,
        "actor_type" character varying(255)
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_status_history_actor_id_index" ON #{quoted}."base_workflow_status_history" (actor_id)|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "idx_flow_lookup" ON #{quoted}."base_workflow_status_history" (flow, flow_id, transitioned_at)|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "idx_flow_status" ON #{quoted}."base_workflow_status_history" (flow, status, transitioned_at)|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "idx_tat_sla" ON #{quoted}."base_workflow_status_history" (flow, status, tat)|,
      []
    )

    SQL.query!(
      repo,
      """
      CREATE TABLE #{quoted}."base_workflow_kanban_columns" (
        id bigserial PRIMARY KEY,
        "flow" character varying(255) NOT NULL,
        "code" character varying(255) NOT NULL,
        "label" character varying(255) NOT NULL,
        "position" integer NOT NULL DEFAULT 0,
        "wip_limit" integer,
        "settings" json,
        "description" text,
        "is_active" boolean NOT NULL DEFAULT true,
        "created_at" timestamp(0) without time zone,
        "updated_at" timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      repo,
      ~s|ALTER TABLE #{quoted}."base_workflow_kanban_columns" ADD CONSTRAINT "base_workflow_kanban_columns_flow_code_unique" UNIQUE (flow, code)|,
      []
    )

    SQL.query!(
      repo,
      ~s|CREATE INDEX "base_workflow_kanban_columns_flow_is_active_position_index" ON #{quoted}."base_workflow_kanban_columns" (flow, is_active, "position")|,
      []
    )

    :ok
  end
end
