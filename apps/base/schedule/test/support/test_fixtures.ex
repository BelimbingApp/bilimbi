defmodule Bilimbi.Base.Schedule.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_schedule_tables! do
    Enum.each(statements(), &SQL.query!(Repo, &1, []))
  end

  defp statements do
    [
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_schedule_runs (
        id bigserial PRIMARY KEY,
        source varchar(40) NOT NULL DEFAULT 'scheduler',
        key varchar(255) NOT NULL,
        name varchar(255) NOT NULL,
        expression varchar(64),
        status varchar(20) NOT NULL,
        started_at timestamp(0) without time zone NOT NULL,
        finished_at timestamp(0) without time zone,
        exit_code integer,
        runtime_ms integer,
        output_excerpt text,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      "CREATE INDEX IF NOT EXISTS base_schedule_runs_source_index ON base_schedule_runs (source)",
      "CREATE INDEX IF NOT EXISTS base_schedule_runs_key_index ON base_schedule_runs (key)",
      "CREATE INDEX IF NOT EXISTS base_schedule_runs_name_index ON base_schedule_runs (name)",
      "CREATE INDEX IF NOT EXISTS base_schedule_runs_status_index ON base_schedule_runs (status)",
      "CREATE INDEX IF NOT EXISTS base_schedule_runs_started_at_index ON base_schedule_runs (started_at)",
      """
      CREATE INDEX IF NOT EXISTS base_schedule_runs_task_started_index
        ON base_schedule_runs (source, key, started_at)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_schedule_suppressions (
        id bigserial PRIMARY KEY,
        source varchar(40) NOT NULL DEFAULT 'scheduler',
        key varchar(255) NOT NULL,
        name varchar(255) NOT NULL,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_schedule_suppressions_source_key_unique
        ON base_schedule_suppressions (source, key)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_schedule_definition_reviews (
        id bigserial PRIMARY KEY,
        source varchar(40) NOT NULL,
        key varchar(255) NOT NULL,
        fingerprint varchar(64) NOT NULL,
        enabled boolean NOT NULL DEFAULT false,
        reviewed_at timestamp(6) with time zone NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_schedule_definition_reviews_source_key_unique
        ON base_schedule_definition_reviews (source, key)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_schedule_occurrences (
        id bigserial PRIMARY KEY,
        source varchar(40) NOT NULL,
        key varchar(255) NOT NULL,
        intended_at timestamp(6) with time zone NOT NULL,
        trigger varchar(20) NOT NULL,
        overlap_key varchar(296),
        state varchar(20) NOT NULL,
        job_id bigint,
        claimed_at timestamp(6) with time zone NOT NULL,
        started_at timestamp(6) with time zone,
        finished_at timestamp(6) with time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_schedule_occurrences_intended_unique
        ON base_schedule_occurrences (source, key, intended_at, trigger)
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_schedule_occurrences_active_overlap_unique
        ON base_schedule_occurrences (overlap_key)
        WHERE overlap_key IS NOT NULL AND finished_at IS NULL
      """,
      """
      CREATE INDEX IF NOT EXISTS base_schedule_occurrences_state_claimed_index
        ON base_schedule_occurrences (state, claimed_at)
      """
    ]
  end
end
