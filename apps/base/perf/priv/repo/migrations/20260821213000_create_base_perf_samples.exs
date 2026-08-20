defmodule Bilimbi.Base.Perf.Migrations.CreateSamples do
  use Ecto.Migration

  def up do
    create table(:base_perf_samples, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:kind, :string, size: 16, null: false)
      add(:identity, :string, size: 255, null: false)
      add(:outcome, :string, size: 16, null: false)
      add(:duration_ms, :bigint, null: false)
      add(:db_duration_ms, :bigint, null: false, default: 0)
      add(:db_count, :integer, null: false, default: 0)
      add(:response_size_class, :string, size: 16)
      add(:memory_bytes, :bigint)
      add(:run_queue, :integer)
      add(:observed_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:base_perf_samples, :base_perf_samples_kind_check,
        check: "kind IN ('request', 'job', 'runtime')"
      )
    )

    create(
      constraint(:base_perf_samples, :base_perf_samples_outcome_check,
        check: "outcome IN ('ok', 'error', 'cancelled', 'discarded')"
      )
    )

    create(
      constraint(:base_perf_samples, :base_perf_samples_identity_check,
        check:
          "(kind = 'request' AND identity ~ '^/[A-Za-z0-9_/:.*-]{0,254}$' " <>
            "AND position('?' in identity) = 0) OR " <>
            "(kind = 'job' AND identity ~ '^[a-z0-9][a-z0-9_/-]{0,127}$') OR " <>
            "(kind = 'runtime' AND identity = 'beam')"
      )
    )

    create(
      constraint(:base_perf_samples, :base_perf_samples_nonnegative_check,
        check:
          "duration_ms >= 0 AND db_duration_ms >= 0 AND db_count >= 0 " <>
            "AND (memory_bytes IS NULL OR memory_bytes >= 0) " <>
            "AND (run_queue IS NULL OR run_queue >= 0)"
      )
    )

    create(
      index(:base_perf_samples, [:observed_at, :id], name: :base_perf_samples_observed_index)
    )

    create(
      index(:base_perf_samples, [:kind, :identity, :observed_at, :id],
        name: :base_perf_samples_identity_window_index
      )
    )
  end

  def down do
    table = qualified_table("base_perf_samples")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM #{table} LIMIT 1) THEN
        RAISE EXCEPTION 'cannot roll back Base Perf while performance history exists';
      END IF;
    END
    $$
    """)

    drop(table(:base_perf_samples))
  end

  defp qualified_table(table_name) do
    case prefix() do
      nil -> quote_identifier(table_name)
      migration_prefix -> "#{quote_identifier(migration_prefix)}.#{quote_identifier(table_name)}"
    end
  end

  defp quote_identifier(identifier), do: "\"#{String.replace(identifier, "\"", "\"\"")}\""
end
