defmodule Bilimbi.Base.Authz.Evaluator do
  @moduledoc false

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.EffectivePermissions
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Tenancy.Scope

  @spec can(Actor.t(), String.t(), Resource.t() | nil, map(), map()) :: Decision.t()
  def can(%Actor{} = actor, capability, resource, _context, registry)
      when is_binary(capability) and is_map(registry) do
    capability = String.downcase(capability)
    directory = registry.company_directory
    policies = ["actor_context"]

    cond do
      is_nil(directory) or not directory.company_in_scope?(actor.scope, actor.company_id) ->
        Decision.deny(:denied_invalid_actor_context, policies)

      capability not in registry.capabilities ->
        Decision.deny(:denied_unknown_capability, policies ++ ["capability_registry"])

      tenant_mismatch?(actor, resource) ->
        Decision.deny(
          :denied_tenant_scope,
          policies ++ ["capability_registry", "tenant_scope"]
        )

      company_mismatch?(actor, resource) ->
        Decision.deny(
          :denied_company_scope,
          policies ++ ["capability_registry", "tenant_scope", "company_scope"]
        )

      true ->
        actor
        |> EffectivePermissions.load(directory)
        |> EffectivePermissions.evaluate(capability, [
          "actor_context",
          "capability_registry",
          "tenant_scope",
          "company_scope",
          "grant"
        ])
    end
  rescue
    _error -> Decision.deny(:denied_policy_engine_error, ["policy_engine"])
  end

  defp tenant_mismatch?(_actor, nil), do: false
  defp tenant_mismatch?(_actor, %Resource{scope: nil}), do: false

  defp tenant_mismatch?(actor, %Resource{scope: resource_scope}) do
    Scope.tenant_id(actor.scope) != Scope.tenant_id(resource_scope)
  end

  defp company_mismatch?(_actor, nil), do: false
  defp company_mismatch?(_actor, %Resource{company_id: nil}), do: false

  defp company_mismatch?(actor, %Resource{company_id: company_id}) do
    actor.company_id != company_id
  end
end
