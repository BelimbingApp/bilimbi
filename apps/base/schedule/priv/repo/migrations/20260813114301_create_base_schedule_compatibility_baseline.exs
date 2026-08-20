defmodule Bilimbi.Base.Schedule.Migrations.CreateCompatibilityBaseline do
  # Compatible baselines precede every Bilimbi-only runtime migration.
  use Ecto.Migration

  def up do
    create table(:base_schedule_runs, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :source, :string, size: 40, null: false, default: "scheduler"
      add :key, :string, size: 255, null: false
      add :name, :string, size: 255, null: false
      add :expression, :string, size: 64
      add :status, :string, size: 20, null: false
      add :started_at, :naive_datetime, null: false
      add :finished_at, :naive_datetime
      add :exit_code, :integer
      add :runtime_ms, :integer
      add :output_excerpt, :text
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create index(:base_schedule_runs, [:source])
    create index(:base_schedule_runs, [:key])
    create index(:base_schedule_runs, [:name])
    create index(:base_schedule_runs, [:status])
    create index(:base_schedule_runs, [:started_at])

    create index(:base_schedule_runs, [:source, :key, :started_at],
             name: :base_schedule_runs_task_started_index
           )

    create table(:base_schedule_suppressions, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :source, :string, size: 40, null: false, default: "scheduler"
      add :key, :string, size: 255, null: false
      add :name, :string, size: 255, null: false
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:base_schedule_suppressions, [:source, :key],
             name: :base_schedule_suppressions_source_key_unique
           )
  end

  def down do
    runs = qualified_table("base_schedule_runs")
    suppressions = qualified_table("base_schedule_suppressions")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM #{runs} LIMIT 1)
         OR EXISTS (SELECT 1 FROM #{suppressions} LIMIT 1) THEN
        RAISE EXCEPTION
          'cannot roll back Base Schedule while run history or suppressions exist';
      END IF;
    END
    $$
    """)

    drop table(:base_schedule_suppressions)
    drop table(:base_schedule_runs)
  end

  defp qualified_table(table_name) do
    case prefix() do
      nil -> quote_identifier(table_name)
      migration_prefix -> "#{quote_identifier(migration_prefix)}.#{quote_identifier(table_name)}"
    end
  end

  defp quote_identifier(identifier), do: "\"#{String.replace(identifier, "\"", "\"\"")}\""
end
