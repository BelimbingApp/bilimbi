defmodule Bilimbi.Base.Audit.Migrations.AddTenantTimelineIndexes do
  use Ecto.Migration

  def change do
    create(
      index(:base_audit_mutations, [:tenant_id, desc(:occurred_at), desc(:id)],
        name: :base_audit_mutations_tenant_timeline_index
      )
    )

    create(
      index(:base_audit_actions, [:tenant_id, desc(:occurred_at), desc(:id)],
        name: :base_audit_actions_tenant_timeline_index
      )
    )
  end
end
