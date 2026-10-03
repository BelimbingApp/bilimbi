defmodule Bilimbi.Base.Schedule.Migrations.IndexAndPruneScheduleOccurrences do
  use Ecto.Migration

  def change do
    create(
      index(:base_schedule_occurrences, [:claimed_at, :id],
        name: :base_schedule_occurrences_unfinished_claimed_index,
        where: "finished_at IS NULL AND job_id IS NOT NULL"
      )
    )
  end
end
