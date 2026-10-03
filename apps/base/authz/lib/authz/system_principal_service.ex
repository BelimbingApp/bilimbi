defmodule Bilimbi.Base.Authz.SystemPrincipalService do
  @moduledoc false
  # Grants, revocations, and decisions for named system principals (ADR 0017).
  #
  # Callers are `Bilimbi.Base.Authz`, which admits only an administrator, and
  # `mix bilimbi.authz.system_principal`, the operator's shell path. Every
  # grant and revocation records who made it as an audit action in the same
  # transaction; if the action cannot be recorded, the change is rolled back.

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Authz.SystemPrincipalCapability
  alias Bilimbi.Base.Authz.SystemPrincipalGrant
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals

  @type granter :: %{
          required(:actor_type) => String.t(),
          required(:actor_id) => non_neg_integer(),
          optional(:company_id) => pos_integer() | nil,
          optional(:impersonator_id) => pos_integer() | nil
        }

  @spec grant(Scope.t(), term(), term(), term(), granter(), map()) ::
          {:ok, :granted | :existing}
          | {:error,
             :undeclared_system_principal
             | :capability_not_declared
             | :company_not_found
             | :audit_unavailable
             | {:unknown_capabilities, [String.t()]}}
  def grant(%Scope{} = scope, company_id, principal, capability, granter, registry)
      when is_binary(capability) do
    capability = String.downcase(capability)

    with {:ok, declared} <- SystemPrincipals.fetch(principal),
         :ok <- known(capability, registry),
         :ok <- declared_capability(declared, capability),
         :ok <- company_in_scope(scope, company_id, registry) do
      transaction(fn ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        {count, _rows} =
          Repo.insert_all(
            SystemPrincipalCapability,
            [
              %{
                company_id: company_id,
                principal: principal,
                capability_key: capability,
                created_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing,
            conflict_target: [:company_id, :principal, :capability_key]
          )

        if count == 1 do
          record!(
            scope,
            "authz.system_principal.granted",
            company_id,
            principal,
            capability,
            granter
          )

          :granted
        else
          :existing
        end
      end)
    end
  end

  def grant(_scope, _company_id, _principal, capability, _granter, _registry),
    do: {:error, {:unknown_capabilities, [inspect(capability)]}}

  @spec revoke(Scope.t(), term(), term(), term(), granter(), map()) ::
          {:ok, :revoked | :not_found} | {:error, :audit_unavailable}
  def revoke(%Scope{} = scope, company_id, principal, capability, granter, registry)
      when is_integer(company_id) and is_binary(principal) and is_binary(capability) do
    capability = String.downcase(capability)
    company_ids = directory!(registry).company_ids(scope)

    transaction(fn ->
      {count, _rows} =
        Repo.delete_all(
          from(grant in SystemPrincipalCapability,
            where: grant.company_id == ^company_id and grant.company_id in ^company_ids,
            where: grant.principal == ^principal and grant.capability_key == ^capability
          )
        )

      if count == 1 do
        record!(
          scope,
          "authz.system_principal.revoked",
          company_id,
          principal,
          capability,
          granter
        )

        :revoked
      else
        :not_found
      end
    end)
  end

  def revoke(_scope, _company_id, _principal, _capability, _granter, _registry),
    do: {:ok, :not_found}

  @spec list(Scope.t(), keyword(), map()) :: [SystemPrincipalGrant.t()]
  def list(%Scope{} = scope, opts, registry) when is_list(opts) do
    company_ids = directory!(registry).company_ids(scope)

    SystemPrincipalCapability
    |> where([grant], grant.company_id in ^company_ids)
    |> filter_principal(Keyword.get(opts, :principal))
    |> order_by([grant], asc: grant.principal, asc: grant.company_id, asc: grant.capability_key)
    |> Repo.all()
    |> Enum.map(fn grant ->
      %SystemPrincipalGrant{
        id: grant.id,
        company_id: grant.company_id,
        principal: grant.principal,
        capability: grant.capability_key,
        granted_at: grant.created_at
      }
    end)
  end

  @doc false
  # Whether the scope's named system principal may perform `capability`.
  # Only an explicit grant allows: there are no roles, no `grant_all`, and
  # nothing a module's declaration grants by itself.
  @spec evaluate(Scope.t(), String.t(), pos_integer(), String.t(), Resource.t() | nil, map()) ::
          Decision.t()
  def evaluate(%Scope{} = scope, principal, company_id, capability, resource, registry) do
    capability = String.downcase(capability)
    directory = registry.company_directory
    policies = ["actor_context"]

    cond do
      is_nil(directory) or not directory.company_in_scope?(scope, company_id) ->
        Decision.deny(:denied_invalid_actor_context, policies)

      not SystemPrincipals.declared?(principal) ->
        Decision.deny(:denied_invalid_actor_context, policies ++ ["system_principal_declaration"])

      capability not in registry.capabilities ->
        Decision.deny(:denied_unknown_capability, policies ++ ["capability_registry"])

      capability in registry.platform_capabilities and not Scope.platform_operator?(scope) ->
        Decision.deny(
          :denied_platform_scope,
          policies ++ ["capability_registry", "platform_operator"]
        )

      tenant_mismatch?(scope, resource) ->
        Decision.deny(:denied_tenant_scope, policies ++ ["capability_registry", "tenant_scope"])

      company_mismatch?(company_id, resource) ->
        Decision.deny(
          :denied_company_scope,
          policies ++ ["capability_registry", "tenant_scope", "company_scope"]
        )

      granted?(company_id, principal, capability) ->
        Decision.allow(
          policies ++
            ["capability_registry", "tenant_scope", "company_scope", "system_principal_grant"]
        )

      true ->
        Decision.deny(
          :denied_missing_capability,
          policies ++
            ["capability_registry", "tenant_scope", "company_scope", "system_principal_grant"]
        )
    end
  rescue
    _error -> Decision.deny(:denied_policy_engine_error, ["policy_engine"])
  end

  # A grant a module no longer declares is inert: the principal may hold only
  # what its module says it needs.
  defp granted?(company_id, principal, capability) do
    {:ok, declared} = SystemPrincipals.fetch(principal)

    capability in declared.capabilities and
      Repo.exists?(
        from(grant in SystemPrincipalCapability,
          where: grant.company_id == ^company_id and grant.principal == ^principal,
          where: grant.capability_key == ^capability
        )
      )
  end

  defp known(capability, registry) do
    if capability in registry.capabilities,
      do: :ok,
      else: {:error, {:unknown_capabilities, [capability]}}
  end

  defp declared_capability(%{capabilities: capabilities}, capability) do
    if capability in capabilities, do: :ok, else: {:error, :capability_not_declared}
  end

  defp company_in_scope(scope, company_id, registry) do
    if is_integer(company_id) and company_id > 0 and
         directory!(registry).company_in_scope?(scope, company_id),
       do: :ok,
       else: {:error, :company_not_found}
  end

  defp filter_principal(query, nil), do: query

  defp filter_principal(query, principal) when is_binary(principal),
    do: where(query, [grant], grant.principal == ^principal)

  defp tenant_mismatch?(_scope, nil), do: false
  defp tenant_mismatch?(_scope, %Resource{scope: nil}), do: false

  defp tenant_mismatch?(scope, %Resource{scope: resource_scope}),
    do: Scope.tenant_id(scope) != Scope.tenant_id(resource_scope)

  defp company_mismatch?(_company_id, nil), do: false
  defp company_mismatch?(_company_id, %Resource{company_id: nil}), do: false

  defp company_mismatch?(company_id, %Resource{company_id: resource_company}),
    do: company_id != resource_company

  defp transaction(fun) do
    Repo.transaction(fun)
  end

  defp record!(scope, event, company_id, principal, capability, granter) do
    context = AuditContext.get()
    verb = if event == "authz.system_principal.granted", do: "Granted", else: "Revoked"

    attributes = %{
      company_id: Map.get(granter, :company_id),
      actor_type: granter.actor_type,
      actor_id: granter.actor_id,
      impersonator_id: Map.get(granter, :impersonator_id),
      system_principal: nil,
      ip_address: context.ip_address,
      url: context.url,
      user_agent: context.user_agent && String.slice(context.user_agent, 0, 80),
      trace_id: context.trace_id && String.slice(context.trace_id, 0, 12),
      event: event,
      payload: %{
        "semantic" => true,
        "source" => "Authz",
        "summary" => "#{verb} #{capability} for #{principal} in company #{company_id}",
        "subject" => %{"name" => "system_principal", "id" => principal, "label" => principal},
        "context" => %{
          "system_principal" => principal,
          "company_id" => company_id,
          "capability" => capability
        },
        "result" => "succeeded"
      },
      is_retained: true,
      occurred_at: NaiveDateTime.utc_now()
    }

    case Audit.record_action(scope, attributes) do
      {:ok, _action} -> :ok
      {:error, _changeset} -> Repo.rollback(:audit_unavailable)
    end
  end

  defp directory!(%{company_directory: nil}) do
    raise ArgumentError, "no installed module contributes the Authz company directory"
  end

  defp directory!(%{company_directory: directory}), do: directory
end
