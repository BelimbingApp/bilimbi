defmodule Bilimbi.Base.Schedule.Migrations.AddTriggerProvenanceToRuns do
  @moduledoc false

  # Belimbing `0100_01_23_000002_add_trigger_provenance_to_base_schedule_runs_table`
  # (upstream, after the first Schedule baseline): how a run was started.
  # `trigger` is `scheduled` (the ticker) or `manual` (an operator's Run now),
  # distinct from `source`, which says what ran. The two `triggered_by`
  # columns name the person behind a manual run, denormalised at dispatch so
  # history never needs a Base-to-Core read. No foreign key: Base must not
  # depend on Core's users table.
  use Ecto.Migration

  def change do
    alter table(:base_schedule_runs) do
      add :trigger, :string, size: 20, null: false, default: "scheduled"
      add :triggered_by_user_id, :bigint
      add :triggered_by_name, :string, size: 255
    end

    create index(:base_schedule_runs, [:triggered_by_user_id],
             name: :base_schedule_runs_triggered_by_user_id_index
           )
  end
end
