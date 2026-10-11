defmodule Bilimbi.Base.Media.Attribution do
  @moduledoc false
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Tenancy.Scope

  def run(scope, fun) do
    actor = Scope.actor(scope)
    previous = Context.get()

    Context.put(%{
      previous
      | actor_type: actor_type(actor),
        actor_id: actor.user_id || 0,
        company_id: actor.company_id,
        tenant_id: Scope.tenant_id(scope),
        impersonator_id: actor.impersonator_id,
        system_principal: actor.system_principal
    })

    try do
      fun.()
    after
      Context.put(previous)
    end
  end

  defp actor_type(%{type: :user}), do: "user"
  defp actor_type(%{system_principal: nil}), do: "guest"
  defp actor_type(_actor), do: "system"
end
