Code.require_file(
  Path.expand("../../priv/repo/migrations/20261013120000_harden_audit_evidence.exs", __DIR__)
)

defmodule Bilimbi.Base.Audit.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Database.TestTables
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  # Simulate loss of the actions store on this sandbox connection only.
  # Its mutable metadata has a foreign key, and a persistent audit table must
  # never become a fallback when the temporary fixture is removed.
  def make_actions_unavailable! do
    SQL.query!(Repo, "SET LOCAL search_path TO pg_temp", [])
    SQL.query!(Repo, "DROP TABLE pg_temp.base_audit_actions CASCADE", [])
    :ok
  end

  def action_payloads(event) do
    SQL.query!(Repo, "SELECT payload FROM base_audit_actions WHERE event = $1 ORDER BY id", [
      event
    ]).rows
  end

  def create_audit_tables!(opts \\ []) do
    persistent = TestTables.persistent?(opts)

    SQL.query!(
      Repo,
      """
      #{TestTables.create(persistent)} IF NOT EXISTS base_audit_mutations (
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
        occurred_at timestamp(0) without time zone NOT NULL,
        impersonator_id bigint,
        system_principal varchar(100)
      ) #{TestTables.on_commit(persistent)}
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_impersonator_id_index
        ON base_audit_mutations (impersonator_id)
        WHERE impersonator_id IS NOT NULL
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_mutations_system_principal_index
        ON base_audit_mutations (system_principal)
        WHERE system_principal IS NOT NULL
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
      #{TestTables.create(persistent)} IF NOT EXISTS base_audit_actions (
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
        occurred_at timestamp(0) without time zone NOT NULL,
        impersonator_id bigint,
        system_principal varchar(100)
      ) #{TestTables.on_commit(persistent)}
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_impersonator_id_index
        ON base_audit_actions (impersonator_id)
        WHERE impersonator_id IS NOT NULL
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX IF NOT EXISTS base_audit_actions_system_principal_index
        ON base_audit_actions (system_principal)
        WHERE system_principal IS NOT NULL
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

    # Apply the exact production evidence DDL to the owner's fixture tables.
    # Each sandbox creates these tables once; persistent host fixtures do too.
    unless SQL.query!(
             Repo,
             "SELECT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'base_audit_actions'::regclass AND attname = 'recorded_at')",
             []
           ).rows == [[true]] do
      unless Code.ensure_loaded?(Bilimbi.Base.Audit.Migrations.HardenAuditEvidence) do
        Code.require_file(
          Application.app_dir(
            :bilimbi_base_audit,
            "priv/repo/migrations/20261013120000_harden_audit_evidence.exs"
          )
        )
      end

      prefix =
        if persistent,
          do: SQL.query!(Repo, "SELECT current_schema()", []).rows |> hd() |> hd(),
          else: nil

      Enum.each(
        Bilimbi.Base.Audit.Migrations.HardenAuditEvidence.statements(not persistent, prefix),
        fn statement ->
          SQL.query!(Repo, statement, [])
        end
      )
    end
  end
end
