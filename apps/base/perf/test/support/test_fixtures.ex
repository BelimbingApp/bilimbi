defmodule Bilimbi.Base.Perf.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_perf_table! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_perf_samples (
        id bigserial PRIMARY KEY,
        kind varchar(16) NOT NULL,
        identity varchar(255) NOT NULL,
        outcome varchar(16) NOT NULL,
        duration_ms bigint NOT NULL,
        db_duration_ms bigint NOT NULL DEFAULT 0,
        db_count integer NOT NULL DEFAULT 0,
        response_size_class varchar(16),
        memory_bytes bigint,
        run_queue integer,
        observed_at timestamp(6) without time zone NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end
end
