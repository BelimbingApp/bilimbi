defmodule Bilimbi.Base.Authz do
  @moduledoc """
  Public authorization API over immutable capability definitions and persisted grants.

  Unknown capabilities fail closed. Direct denies override direct allows,
  `grant_all`, and role grants. Source discovery never mutates assignments;
  configured system roles are reconciled only by the explicit production-seed path.
  """

  import Ecto.Query

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.AuthorizationDeniedError
  alias Bilimbi.Base.Authz.DatabaseDecisionLogger
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.Diagnostics
  alias Bilimbi.Base.Authz.EffectivePermissions
  alias Bilimbi.Base.Authz.Evaluator
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Authz.RoleService
  alias Bilimbi.Base.Authz.SystemRoleReconciler
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy.Scope

  @spec actor(:user | :agent, pos_integer(), Scope.t(), pos_integer(), keyword()) :: Actor.t()
  def actor(type, id, %Scope{} = scope, company_id, opts \\ []) do
    Actor.new!(type, id, scope, company_id, opts)
  end

  @spec resource(String.t(), String.t() | integer() | nil, keyword()) :: Resource.t()
  def resource(type, id \\ nil, opts \\ []), do: Resource.new!(type, id, opts)

  @spec capabilities() :: [String.t()]
  def capabilities, do: registry!().capabilities

  @spec capability_known?(String.t()) :: boolean()
  def capability_known?(capability) when is_binary(capability) do
    String.downcase(capability) in capabilities()
  end

  @spec system_role_definitions() :: %{required(String.t()) => map()}
  def system_role_definitions, do: registry!().roles

  @spec can(Actor.t(), String.t(), Resource.t() | nil, map()) :: Decision.t()
  def can(%Actor{} = actor, capability, resource \\ nil, context \\ %{})
      when is_binary(capability) and is_map(context) do
    decision = Evaluator.can(actor, capability, resource, context, registry!())
    :ok = DatabaseDecisionLogger.log(actor, capability, resource, decision, context)
    decision
  end

  @spec authorize!(Actor.t(), String.t(), Resource.t() | nil, map()) :: :ok
  def authorize!(%Actor{} = actor, capability, resource \\ nil, context \\ %{}) do
    case can(actor, capability, resource, context) do
      %Decision{allowed: true} -> :ok
      %Decision{} = decision -> raise AuthorizationDeniedError, decision: decision
    end
  end

  @spec filter_allowed(Actor.t(), String.t(), Enumerable.t(), map()) :: list()
  def filter_allowed(%Actor{} = actor, capability, resources, context \\ %{}) do
    resources
    |> Enum.filter(fn
      %Resource{} = resource -> can(actor, capability, resource, context).allowed
      other -> raise ArgumentError, "expected an Authz resource, got: #{inspect(other)}"
    end)
  end

  @spec effective_capabilities(Actor.t()) :: %{allowed: [String.t()], denied: [String.t()]}
  def effective_capabilities(%Actor{} = actor) do
    registry = registry!()
    directory = directory!(registry)
    permissions = EffectivePermissions.load(actor, directory)

    %{
      allowed: EffectivePermissions.allowed(permissions, registry.capabilities),
      denied: EffectivePermissions.denied(permissions)
    }
  end

  @spec list_roles(Scope.t()) :: [Bilimbi.Base.Authz.RoleSummary.t()]
  def list_roles(%Scope{} = scope), do: RoleService.list_roles(scope, registry!())

  @spec create_role(Scope.t(), pos_integer(), map()) ::
          {:ok, Bilimbi.Base.Authz.RoleSummary.t()}
          | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_role(%Scope{} = scope, company_id, attributes) do
    RoleService.create_role(scope, company_id, attributes, registry!())
  end

  @spec replace_role_capabilities(Scope.t(), pos_integer(), [String.t()]) ::
          {:ok, non_neg_integer()}
          | {:error, :role_not_found | :system_role | {:unknown_capabilities, [String.t()]}}
  def replace_role_capabilities(%Scope{} = scope, role_id, capabilities) do
    RoleService.replace_role_capabilities(scope, role_id, capabilities, registry!())
  end

  @spec assign_role(Scope.t(), pos_integer(), :user | :agent, pos_integer(), pos_integer()) ::
          {:ok, :assigned | :existing} | {:error, :company_not_found | :role_not_found}
  def assign_role(%Scope{} = scope, company_id, principal_type, principal_id, role_id) do
    RoleService.assign_role(
      scope,
      company_id,
      principal_type,
      principal_id,
      role_id,
      registry!()
    )
  end

  @spec put_principal_capability(
          Scope.t(),
          pos_integer(),
          :user | :agent,
          pos_integer(),
          String.t(),
          boolean()
        ) ::
          {:ok, :stored}
          | {:error, :company_not_found | {:unknown_capabilities, [String.t()]}}
  def put_principal_capability(
        %Scope{} = scope,
        company_id,
        principal_type,
        principal_id,
        capability,
        allowed?
      ) do
    RoleService.put_principal_capability(
      scope,
      company_id,
      principal_type,
      principal_id,
      capability,
      allowed?,
      registry!()
    )
  end

  @spec reconcile_system_roles(keyword()) ::
          {:ok, %{roles: non_neg_integer(), capabilities: non_neg_integer()}} | {:error, term()}
  def reconcile_system_roles(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    SystemRoleReconciler.reconcile(repo, registry!())
  end

  @spec unknown_persisted_capabilities() :: map()
  def unknown_persisted_capabilities do
    Diagnostics.unknown_persisted_capabilities(capabilities())
  end

  @spec prune_decision_logs() :: non_neg_integer()
  def prune_decision_logs do
    days = Settings.get("authz.decision_log_retention_days")
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86_400, :second)
    {count, _rows} = Repo.delete_all(from(log in DecisionLog, where: log.occurred_at < ^cutoff))
    count
  end

  defp registry!, do: ContributionRegistry.consumer!(:authz)

  defp directory!(%{company_directory: nil}) do
    raise ArgumentError, "no installed module contributes the Authz company directory"
  end

  defp directory!(%{company_directory: directory}), do: directory
end
