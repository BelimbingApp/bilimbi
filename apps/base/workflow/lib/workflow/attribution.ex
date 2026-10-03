defmodule Bilimbi.Base.Workflow.Attribution do
  @moduledoc false
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope

  # Every Workflow write runs in one Repo transaction whose captured mutations
  # carry the sealed Scope actor, impersonation included. Callers decide which
  # actors may write; this only attributes and restores the previous context.
  def transact(scope, fun) do
    actor = Scope.actor(scope)
    previous = AuditContext.get()

    AuditContext.put(%{
      previous
      | tenant_id: Scope.tenant_id(scope),
        company_id: actor.company_id,
        actor_type: Atom.to_string(actor.type),
        actor_id: actor.user_id || 0,
        impersonator_id: actor.impersonator_id,
        system_principal: actor.system_principal
    })

    try do
      Repo.transact(fun)
    after
      AuditContext.put(previous)
    end
  end
end
