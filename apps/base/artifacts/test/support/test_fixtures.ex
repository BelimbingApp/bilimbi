defmodule Bilimbi.Base.Artifacts.TestFixtures do
  @moduledoc false
  alias Bilimbi.Base.Repo

  # Mirrors the owned migrations; the guard functions live in pg_temp so they
  # vanish with the sandbox session. `migration_guard_test.exs` proves the
  # shipped DDL itself, so a drift between the two fails there.
  def create_artifacts_table! do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE base_artifacts (
        id uuid PRIMARY KEY,
        tenant_id bigint NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
        company_id bigint NOT NULL CONSTRAINT base_artifacts_company_positive CHECK (company_id > 0),
        owner_id varchar(255) NOT NULL,
        owner_adapter varchar(255) NOT NULL,
        subject varchar(255) NOT NULL,
        kind varchar(255) NOT NULL,
        content_type varchar(255) NOT NULL,
        byte_size bigint NOT NULL CONSTRAINT base_artifacts_bytes_positive CHECK (byte_size > 0),
        sha256 varchar(64) NOT NULL,
        storage_root text NOT NULL,
        expires_at timestamp(6),
        retain_until timestamp(6),
        legal_hold_at timestamp(6),
        ready_at timestamp(6), deleted_at timestamp(6), purged_at timestamp(6),
        purge_attempts integer NOT NULL DEFAULT 0, purge_last_error varchar(255),
        purge_attempted_at timestamp(6), purge_held_at timestamp(6),
        inserted_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL,
        CONSTRAINT base_artifacts_retention_exclusive
          CHECK ((retain_until IS NULL) <> (expires_at IS NULL)),
        CONSTRAINT base_artifacts_hold_requires_retention
          CHECK (legal_hold_at IS NULL OR retain_until IS NOT NULL)
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE INDEX base_artifacts_retention_index ON base_artifacts
        (tenant_id, company_id, owner_id, expires_at)
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE base_artifact_retention_events (
        id bigserial PRIMARY KEY,
        artifact_id uuid NOT NULL REFERENCES base_artifacts(id) ON DELETE RESTRICT,
        tenant_id bigint NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
        company_id bigint NOT NULL
          CONSTRAINT base_artifact_retention_events_company_positive CHECK (company_id > 0),
        owner_id varchar(255) NOT NULL,
        event varchar(40) NOT NULL CONSTRAINT base_artifact_retention_events_event_check
          CHECK (event IN ('retained', 'retention_extended', 'hold_placed', 'hold_released')),
        retain_until timestamp(6) NOT NULL,
        legal_hold boolean NOT NULL,
        reason varchar(255),
        actor_type varchar(40) NOT NULL,
        actor_id bigint NOT NULL,
        impersonator_id bigint,
        system_principal varchar(100),
        recorded_at timestamp(6) NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE INDEX base_artifact_retention_events_artifact_index
        ON base_artifact_retention_events (artifact_id, id)
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE FUNCTION pg_temp.base_artifacts_guard_retention() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF OLD.retain_until IS NOT NULL
             AND (OLD.legal_hold_at IS NOT NULL OR OLD.retain_until > timezone('UTC', now())) THEN
            RAISE EXCEPTION 'base_artifacts row % is retained', OLD.id
              USING ERRCODE = 'check_violation', CONSTRAINT = 'base_artifacts_retention_guard';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.retain_until IS NOT NULL
           AND (NEW.retain_until IS NULL OR NEW.retain_until < OLD.retain_until) THEN
          RAISE EXCEPTION 'base_artifacts row % retention cannot be shortened', OLD.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'base_artifacts_retention_guard';
        END IF;

        IF OLD.retain_until IS NOT NULL
           AND (OLD.legal_hold_at IS NOT NULL OR OLD.retain_until > timezone('UTC', now()))
           AND ((NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
                OR (NEW.purged_at IS NOT NULL AND OLD.purged_at IS NULL)) THEN
          RAISE EXCEPTION 'base_artifacts row % is retained', OLD.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'base_artifacts_retention_guard';
        END IF;

        RETURN NEW;
      END
      $$
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE TRIGGER base_artifacts_retention_guard
        BEFORE UPDATE OR DELETE ON base_artifacts
        FOR EACH ROW EXECUTE FUNCTION pg_temp.base_artifacts_guard_retention()
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE FUNCTION pg_temp.base_artifact_retention_events_guard() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          NEW.recorded_at := timezone('UTC', now());
          RETURN NEW;
        END IF;

        RAISE EXCEPTION 'base_artifact_retention_events is append-only'
          USING ERRCODE = 'check_violation',
                CONSTRAINT = 'base_artifact_retention_events_append_only';
      END
      $$
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE TRIGGER base_artifact_retention_events_append_only
        BEFORE INSERT OR UPDATE OR DELETE ON base_artifact_retention_events
        FOR EACH ROW EXECUTE FUNCTION pg_temp.base_artifact_retention_events_guard()
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE TRIGGER base_artifact_retention_events_no_truncate
        BEFORE TRUNCATE ON base_artifact_retention_events
        FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.base_artifact_retention_events_guard()
      """,
      []
    )
  end
end
