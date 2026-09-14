defmodule Bilimbi.Base.Audit.Migrations.AddImpersonatorToAuditRows do
  @moduledoc """
  Bilimbi-only: records the operator behind an impersonated session.

  `actor_id` keeps naming the account the action was performed as; every
  historical row and every index on the actor pair keeps its meaning. When an
  operator acts while impersonating another user, `impersonator_id` names the
  operator, so a reader can recover both identities from one row. Rows written
  outside impersonation leave it null. Like the actor pair it has no foreign
  key: audit rows outlive their principals.

  Belimbing's pinned schema has no such column; its semantic action recorder
  only carries an `impersonator_id` payload key and its mutation listener
  carries nothing. This divergence is deliberate (ADR 0002 Bilimbi-only
  evolution) and is declared as an optional contribution in the Base Audit
  schema contract, so an adopted Belimbing database verifies before this
  migration runs and after it.
  """

  use Ecto.Migration

  def up do
    alter table(:base_audit_mutations) do
      add :impersonator_id, :bigint
    end

    create index(:base_audit_mutations, [:impersonator_id], where: "impersonator_id IS NOT NULL")

    alter table(:base_audit_actions) do
      add :impersonator_id, :bigint
    end

    create index(:base_audit_actions, [:impersonator_id], where: "impersonator_id IS NOT NULL")
  end

  def down do
    drop_if_exists index(:base_audit_actions, [:impersonator_id])

    alter table(:base_audit_actions) do
      remove :impersonator_id
    end

    drop_if_exists index(:base_audit_mutations, [:impersonator_id])

    alter table(:base_audit_mutations) do
      remove :impersonator_id
    end
  end
end
