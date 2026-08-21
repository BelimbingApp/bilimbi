defmodule Bilimbi.Base.Schedule.Migrations.CreateOccurrenceRuntime do
  use Ecto.Migration

  def up do
    create table(:base_schedule_definition_reviews, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :source, :string, size: 40, null: false
      add :key, :string, size: 255, null: false
      add :fingerprint, :string, size: 64, null: false
      add :enabled, :boolean, null: false, default: false
      add :reviewed_at, :utc_datetime_usec, null: false
    end

    create unique_index(:base_schedule_definition_reviews, [:source, :key],
             name: :base_schedule_definition_reviews_source_key_unique
           )

    create table(:base_schedule_occurrences, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :source, :string, size: 40, null: false
      add :key, :string, size: 255, null: false
      add :intended_at, :utc_datetime_usec, null: false
      add :trigger, :string, size: 20, null: false
      add :overlap_key, :string, size: 296
      add :state, :string, size: 20, null: false
      add :job_id, :bigint
      add :claimed_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
    end

    create unique_index(:base_schedule_occurrences, [:source, :key, :intended_at, :trigger],
             name: :base_schedule_occurrences_intended_unique
           )

    create unique_index(:base_schedule_occurrences, [:overlap_key],
             name: :base_schedule_occurrences_active_overlap_unique,
             where: "overlap_key IS NOT NULL AND finished_at IS NULL"
           )

    create index(:base_schedule_occurrences, [:state, :claimed_at],
             name: :base_schedule_occurrences_state_claimed_index
           )
  end

  def down do
    occurrences = qualified_table("base_schedule_occurrences")
    reviews = qualified_table("base_schedule_definition_reviews")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM #{occurrences} LIMIT 1)
         OR EXISTS (SELECT 1 FROM #{reviews} LIMIT 1) THEN
        RAISE EXCEPTION
          'cannot roll back Base Schedule while occurrence claims or definition reviews exist';
      END IF;
    END
    $$
    """)

    drop table(:base_schedule_occurrences)
    drop table(:base_schedule_definition_reviews)
  end

  defp qualified_table(table_name) do
    case prefix() do
      nil -> quote_identifier(table_name)
      migration_prefix -> "#{quote_identifier(migration_prefix)}.#{quote_identifier(table_name)}"
    end
  end

  defp quote_identifier(identifier), do: "\"#{String.replace(identifier, "\"", "\"\"")}\""
end
