defmodule Bilimbi.Base.Audit.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_audit_tables! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_audit_mutations (
        id bigserial PRIMARY KEY,
        company_id bigint,
        tenant_id bigint,
        actor_type varchar(40) NOT NULL,
        actor_id bigint NOT NULL,
        actor_role varchar(100),
        ip_address inet,
        url text,
        user_agent varchar(80),
        auditable_type varchar(255) NOT NULL,
        auditable_id varchar(128) NOT NULL,
        subject_name varchar(255),
        subject_id varchar(128),
        subject_identifier varchar(255),
        source varchar(20) NOT NULL DEFAULT 'listener',
        event varchar(20) NOT NULL,
        old_values jsonb,
        new_values jsonb,
        trace_id varchar(12),
        occurred_at timestamp(0) without time zone NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_company_id_index
        ON base_audit_mutations (company_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_tenant_id_index
        ON base_audit_mutations (tenant_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_actor_type_index
        ON base_audit_mutations (actor_type)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_actor_id_index
        ON base_audit_mutations (actor_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_auditable_type_index
        ON base_audit_mutations (auditable_type)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_auditable_id_index
        ON base_audit_mutations (auditable_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_source_index
        ON base_audit_mutations (source)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_event_index
        ON base_audit_mutations (event)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_trace_id_index
        ON base_audit_mutations (trace_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_occurred_at_index
        ON base_audit_mutations (occurred_at)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_auditable_occurred_index
        ON base_audit_mutations (auditable_type, auditable_id, occurred_at)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_actor_type_actor_id_occurred_at_index
        ON base_audit_mutations (actor_type, actor_id, occurred_at)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_subject_idx
        ON base_audit_mutations (subject_name, subject_id, subject_identifier, occurred_at)
        WHERE subject_name IS NOT NULL
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_audit_actions (
        id bigserial PRIMARY KEY,
        company_id bigint,
        tenant_id bigint,
        actor_type varchar(40) NOT NULL,
        actor_id bigint NOT NULL,
        actor_role varchar(100),
        ip_address inet,
        url text,
        user_agent varchar(80),
        event varchar(255) NOT NULL,
        payload jsonb,
        trace_id varchar(12),
        is_retained boolean NOT NULL DEFAULT false,
        occurred_at timestamp(0) without time zone NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_company_id_index
        ON base_audit_actions (company_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_tenant_id_index
        ON base_audit_actions (tenant_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_actor_type_index
        ON base_audit_actions (actor_type)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_actor_id_index
        ON base_audit_actions (actor_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_event_index
        ON base_audit_actions (event)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_trace_id_index
        ON base_audit_actions (trace_id)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_occurred_at_index
        ON base_audit_actions (occurred_at)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_event_occurred_at_index
        ON base_audit_actions (event, occurred_at)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_actor_type_actor_id_occurred_at_index
        ON base_audit_actions (actor_type, actor_id, occurred_at)
      """,
      []
    )
  end
end
