defmodule Bilimbi.Base.Artifacts.Migrations.AddRetention do
  use Ecto.Migration

  # Records-grade retention: a retained document has `retain_until` instead of
  # `expires_at`, may carry a legal hold, and every retention change is one
  # append-only event row stamped by PostgreSQL. The triggers are the database
  # guard: the facade refuses first, and the database refuses whatever bypasses
  # it, including a console or a future caller that forgets the check.

  def up do
    alter table(:base_artifacts) do
      modify(:expires_at, :utc_datetime_usec, null: true)
      add(:retain_until, :utc_datetime_usec)
      add(:legal_hold_at, :utc_datetime_usec)
    end

    create(
      constraint(:base_artifacts, :base_artifacts_retention_exclusive,
        check: "(retain_until IS NULL) <> (expires_at IS NULL)"
      )
    )

    create(
      constraint(:base_artifacts, :base_artifacts_hold_requires_retention,
        check: "legal_hold_at IS NULL OR retain_until IS NOT NULL"
      )
    )

    create table(:base_artifact_retention_events) do
      add(
        :artifact_id,
        references(:base_artifacts, type: :uuid, on_delete: :restrict),
        null: false
      )

      add(:tenant_id, references(:tenants, type: :bigint, on_delete: :restrict), null: false)
      add(:company_id, :bigint, null: false)
      add(:owner_id, :string, null: false)
      add(:event, :string, size: 40, null: false)
      add(:retain_until, :utc_datetime_usec, null: false)
      add(:legal_hold, :boolean, null: false)
      add(:reason, :string)
      add(:actor_type, :string, size: 40, null: false)
      add(:actor_id, :bigint, null: false)
      add(:impersonator_id, :bigint)
      add(:system_principal, :string, size: 100)
      # Stamped by the append-only trigger below; the application never sets it.
      add(:recorded_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(
        :base_artifact_retention_events,
        :base_artifact_retention_events_company_positive,
        check: "company_id > 0"
      )
    )

    create(
      constraint(:base_artifact_retention_events, :base_artifact_retention_events_event_check,
        check: "event IN ('retained', 'retention_extended', 'hold_placed', 'hold_released')"
      )
    )

    create(
      index(:base_artifact_retention_events, [:artifact_id, :id],
        name: :base_artifact_retention_events_artifact_index
      )
    )

    execute("""
    CREATE FUNCTION #{qualified("base_artifacts_guard_retention")}() RETURNS trigger
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
    """)

    execute("""
    CREATE TRIGGER base_artifacts_retention_guard
      BEFORE UPDATE OR DELETE ON #{qualified("base_artifacts")}
      FOR EACH ROW EXECUTE FUNCTION #{qualified("base_artifacts_guard_retention")}()
    """)

    execute("""
    CREATE FUNCTION #{qualified("base_artifact_retention_events_guard")}() RETURNS trigger
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
    """)

    execute("""
    CREATE TRIGGER base_artifact_retention_events_append_only
      BEFORE INSERT OR UPDATE OR DELETE ON #{qualified("base_artifact_retention_events")}
      FOR EACH ROW EXECUTE FUNCTION #{qualified("base_artifact_retention_events_guard")}()
    """)

    execute("""
    CREATE TRIGGER base_artifact_retention_events_no_truncate
      BEFORE TRUNCATE ON #{qualified("base_artifact_retention_events")}
      FOR EACH STATEMENT EXECUTE FUNCTION #{qualified("base_artifact_retention_events_guard")}()
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM #{qualified("base_artifact_retention_events")} LIMIT 1) THEN
        RAISE EXCEPTION 'cannot roll back artifact retention while retention events exist';
      END IF;
    END
    $$
    """)

    execute("DROP TABLE #{qualified("base_artifact_retention_events")}")
    execute("DROP FUNCTION #{qualified("base_artifact_retention_events_guard")}()")
    execute("DROP TRIGGER base_artifacts_retention_guard ON #{qualified("base_artifacts")}")
    execute("DROP FUNCTION #{qualified("base_artifacts_guard_retention")}()")
    drop(constraint(:base_artifacts, :base_artifacts_hold_requires_retention))
    drop(constraint(:base_artifacts, :base_artifacts_retention_exclusive))

    alter table(:base_artifacts) do
      remove(:legal_hold_at)
      remove(:retain_until)
      modify(:expires_at, :utc_datetime_usec, null: false)
    end
  end

  defp qualified(name) do
    case prefix() do
      nil -> quote_identifier(name)
      migration_prefix -> "#{quote_identifier(migration_prefix)}.#{quote_identifier(name)}"
    end
  end

  defp quote_identifier(identifier), do: "\"#{String.replace(identifier, "\"", "\"\"")}\""
end
