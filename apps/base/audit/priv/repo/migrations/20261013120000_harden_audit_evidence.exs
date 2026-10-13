defmodule Bilimbi.Base.Audit.Migrations.HardenAuditEvidence do
  use Ecto.Migration

  def up do
    Enum.each(statements(false, prefix()), &execute/1)
  end

  def down do
    schema = Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(prefix() || "public")

    for table <- ~w(base_audit_actions base_audit_mutations base_audit_capture_failures) do
      execute("DROP TRIGGER #{table}_evidence_guard ON #{schema}.#{table}")
      execute("DROP TRIGGER #{table}_truncate_guard ON #{schema}.#{table}")
    end

    execute("DROP FUNCTION #{schema}.base_audit_evidence_v1()")
    drop table(:base_audit_capture_failures)
    drop table(:base_audit_action_metadata)
    alter table(:base_audit_actions), do: remove(:recorded_at)
    alter table(:base_audit_mutations), do: remove(:recorded_at)
  end

  # This migration also supplies the owner's fixture DDL. Keeping it here makes
  # provenance checksums cover the actual evidence guards, clocks, and tables.
  @doc false
  def statements(temporary \\ false, prefix \\ nil) do
    create = if temporary, do: "CREATE TEMPORARY TABLE", else: "CREATE TABLE"

    schema =
      Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(
        prefix || if(temporary, do: "pg_temp", else: "public")
      )

    function = "#{schema}.base_audit_evidence_v1"
    actions = "#{schema}.base_audit_actions"
    mutations = "#{schema}.base_audit_mutations"
    metadata = "#{schema}.base_audit_action_metadata"
    failures = "#{schema}.base_audit_capture_failures"

    [
      "ALTER TABLE #{actions} ADD COLUMN recorded_at timestamp(6) without time zone",
      "ALTER TABLE #{mutations} ADD COLUMN recorded_at timestamp(6) without time zone",
      """
      #{create} #{metadata} (
        action_id bigint PRIMARY KEY REFERENCES #{actions}(id) ON DELETE RESTRICT,
        is_retained boolean NOT NULL DEFAULT false
      )
      """,
      """
      #{create} #{failures} (
        id bigserial PRIMARY KEY,
        action text NOT NULL, schema_name text NOT NULL, error_type text NOT NULL,
        actor_type varchar(40) NOT NULL, actor_id bigint NOT NULL,
        impersonator_id bigint, system_principal varchar(100),
        company_id bigint, tenant_id bigint, trace_id text,
        recorded_at timestamp(6) without time zone NOT NULL
      )
      """,
      """
      CREATE OR REPLACE FUNCTION #{function}() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP != 'INSERT' THEN
          RAISE EXCEPTION 'audit evidence is append-only' USING ERRCODE = '42501';
        END IF;
        NEW.recorded_at := clock_timestamp() AT TIME ZONE 'UTC';
        IF TG_TABLE_NAME != 'base_audit_capture_failures' THEN
          IF NEW.occurred_at IS NULL THEN
            NEW.occurred_at := NEW.recorded_at;
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$
      """
    ] ++
      Enum.flat_map(
        ~w(base_audit_actions base_audit_mutations base_audit_capture_failures),
        fn table ->
          [
            "CREATE TRIGGER #{table}_evidence_guard BEFORE INSERT OR UPDATE OR DELETE ON #{schema}.#{table} FOR EACH ROW EXECUTE FUNCTION #{function}()",
            "CREATE TRIGGER #{table}_truncate_guard BEFORE TRUNCATE ON #{schema}.#{table} FOR EACH STATEMENT EXECUTE FUNCTION #{function}()"
          ]
        end
      )
  end
end
