defmodule Bilimbi.Base.Workflow.Attribution do
  @moduledoc false
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Repo

  # Every Workflow write runs in one Repo transaction whose captured mutations
  # carry the sealed Scope actor, impersonation included. Callers decide which
  # actors may write; this only attributes and restores the previous context.
  def transact(scope, fun), do: attributed(scope, fn -> Repo.transact(fun) end)

  # Attribution without a transaction, for a delivery whose listeners may
  # reach outside the database; their own writes are still captured as the
  # scope's actor.
  def attributed(scope, fun), do: AuditContext.with_scope(scope, fun)

  # The actor columns an audit row records for this scope, the same identity
  # `Bilimbi.Base.Audit.Context.from_scope/1` derives: a named system principal
  # is recorded as itself (ADR 0017), and maintenance nobody signed in for is
  # the anonymous `system` actor, never an invented guest.
  def audit_actor(actor),
    do: %{
      actor_type: Atom.to_string(actor.type),
      actor_id: actor.user_id || 0,
      company_id: actor.company_id,
      impersonator_id: actor.impersonator_id,
      system_principal: actor.system_principal
    }
end
