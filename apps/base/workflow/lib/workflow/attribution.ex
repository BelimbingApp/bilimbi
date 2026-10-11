defmodule Bilimbi.Base.Workflow.Attribution do
  @moduledoc false
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope

  # Every Workflow write runs in one Repo transaction whose captured mutations
  # carry the sealed Scope actor, impersonation included. Callers decide which
  # actors may write; this only attributes and restores the previous context.
  def transact(scope, fun), do: attributed(scope, fn -> Repo.transact(fun) end)

  # Attribution without a transaction, for a delivery whose listeners may
  # reach outside the database; their own writes are still captured as the
  # scope's actor.
  def attributed(scope, fun) do
    actor = Scope.actor(scope)
    previous = AuditContext.get()

    AuditContext.put(
      Map.merge(previous, Map.put(audit_actor(actor), :tenant_id, Scope.tenant_id(scope)))
    )

    try do
      fun.()
    after
      AuditContext.put(previous)
    end
  end

  # The actor columns an audit row records for this scope. A named system
  # principal is recorded as itself (ADR 0017). The anonymous system actor of
  # maintenance that nobody signed in for and no principal was named for is
  # recorded as the guest default, as `apps/base/audit/AGENTS.md` requires:
  # a "system" row must name a principal, and no actor is invented to avoid it.
  def audit_actor(%{type: :system, system_principal: nil}),
    do: %{
      actor_type: "guest",
      actor_id: 0,
      company_id: nil,
      impersonator_id: nil,
      system_principal: nil
    }

  def audit_actor(actor),
    do: %{
      actor_type: Atom.to_string(actor.type),
      actor_id: actor.user_id || 0,
      company_id: actor.company_id,
      impersonator_id: actor.impersonator_id,
      system_principal: actor.system_principal
    }
end
