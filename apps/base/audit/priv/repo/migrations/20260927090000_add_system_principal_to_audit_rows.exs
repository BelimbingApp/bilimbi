defmodule Bilimbi.Base.Audit.Migrations.AddSystemPrincipalToAuditRows do
  @moduledoc """
  Bilimbi-only: records the named system principal a row was written as.

  A job enqueued with `Bilimbi.Base.Queue.enqueue_as_system/4` runs as a
  declared system identity, such as `coating.line_import`, rather than as a user
  (ADR 0017). Its rows record `actor_type` `"system"` and `actor_id` `0`, and
  `system_principal` names the identity, so the trail says which routine did
  the work. Every other row leaves it null. Like the actor pair it has no
  foreign key: audit rows outlive the modules that declared their principals.

  Belimbing's pinned schema has no such column. This divergence is deliberate
  (ADR 0002 Bilimbi-only evolution) and is declared as an optional group in
  the Base Audit schema contract, so an adopted Belimbing database verifies
  before this migration runs and after it.
  """

  use Ecto.Migration

  def up do
    alter table(:base_audit_mutations) do
      add :system_principal, :string, size: 100
    end

    create index(:base_audit_mutations, [:system_principal],
             where: "system_principal IS NOT NULL"
           )

    alter table(:base_audit_actions) do
      add :system_principal, :string, size: 100
    end

    create index(:base_audit_actions, [:system_principal], where: "system_principal IS NOT NULL")
  end

  def down do
    drop_if_exists index(:base_audit_actions, [:system_principal])

    alter table(:base_audit_actions) do
      remove :system_principal
    end

    drop_if_exists index(:base_audit_mutations, [:system_principal])

    alter table(:base_audit_mutations) do
      remove :system_principal
    end
  end
end
