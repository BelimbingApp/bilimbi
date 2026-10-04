defmodule Bilimbi.Base.Authz.Migrations.AddDecisionLogTimelineIndex do
  use Ecto.Migration

  def change do
    create(
      index(:base_authz_decision_logs, [:company_id, desc: :occurred_at, desc: :id],
        name: :base_authz_decision_logs_company_timeline_index
      )
    )
  end
end
