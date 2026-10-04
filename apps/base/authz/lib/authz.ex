defmodule Bilimbi.Base.Authz do
  @moduledoc """
  Public authorization API over immutable capability definitions and persisted grants.

  Unknown capabilities fail closed. Direct denies override direct allows,
  `grant_all`, and role grants. Source discovery never mutates assignments;
  configured system roles are reconciled only by the explicit production-seed path.
  """

  import Ecto.Query

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.Administration
  alias Bilimbi.Base.Authz.AuthorizationDeniedError
  alias Bilimbi.Base.Authz.CapabilitySummary
  alias Bilimbi.Base.Authz.DatabaseDecisionLogger
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.Diagnostics
  alias Bilimbi.Base.Authz.EffectivePermissions
  alias Bilimbi.Base.Authz.Evaluator
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Authz.RoleService
  alias Bilimbi.Base.Authz.SystemPrincipalGrant
  alias Bilimbi.Base.Authz.SystemPrincipalService
  alias Bilimbi.Base.Authz.SystemRoleReconciler
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals

  @doc """
  Builds an authorization principal from IDs the caller names.

  Use this to evaluate a principal other than the one performing the work,
  such as an administration screen previewing another account's access. To
  decide whether the person performing the work may do something, pass the
  scope to `can/4` or `authorize!/4`, or take the principal from
  `scope_actor/1`: those read the actor Bilimbi's authentication edge sealed
  onto the scope, which no caller can assert.
  """
  @spec actor(:user | :agent, pos_integer(), Scope.t(), pos_integer(), keyword()) :: Actor.t()
  def actor(type, id, %Scope{} = scope, company_id, opts \\ []) do
    Actor.new!(type, id, scope, company_id, opts)
  end

  @doc """
  The authorization principal for the user who performs the scope's work.

  A system scope names no user, so it has no principal. That includes a
  named system principal: it may hold capabilities (ask `can/4`), but it is
  never a user who can approve or be recorded as one.
  """
  @spec scope_actor(Scope.t()) :: {:ok, Actor.t()} | {:error, :no_authenticated_actor}
  def scope_actor(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id, company_id: company_id} ->
        {:ok, Actor.new!(:user, user_id, scope, company_id)}

      %TenancyActor{type: :system} ->
        {:error, :no_authenticated_actor}
    end
  end

  @spec resource(String.t(), String.t() | integer() | nil, keyword()) :: Resource.t()
  def resource(type, id \\ nil, opts \\ []), do: Resource.new!(type, id, opts)

  @spec capabilities() :: [String.t()]
  def capabilities, do: registry!().capabilities

  @doc "Lists registered capabilities through a bounded catalog page."
  @spec list_capabilities(keyword()) :: Bilimbi.Base.Authz.Page.t(CapabilitySummary.t())
  def list_capabilities(opts \\ []) when is_list(opts) do
    Administration.list_capabilities(opts, registry!())
  end

  @doc "Lists unique domain names from registered capabilities."
  @spec capability_domains() :: [String.t()]
  def capability_domains do
    Administration.capability_domains(registry!())
  end

  @spec capability_known?(String.t()) :: boolean()
  def capability_known?(capability) when is_binary(capability) do
    String.downcase(capability) in capabilities()
  end

  @doc """
  Decides whether a principal holds `capability`.

  Given a `Bilimbi.Base.Tenancy.Scope`, the principal is the scope's
  authenticated user (see `scope_actor/1`). That is the form for "may the
  person performing this do it": the answer cannot be steered by naming
  somebody else. An anonymous system scope names nobody and is denied with
  `:denied_no_authenticated_actor`; there is no principal to log.

  A scope whose actor is a named system principal (a job enqueued with
  `Bilimbi.Base.Queue.enqueue_as_system/4`, ADR 0017) is judged against that
  principal's grants in the actor's company, and nothing else: no roles, no
  `grant_all`, and only capabilities its module declared. The decision is
  logged with `actor_type` `"system"`, `actor_id` `0`, and the principal's
  name in the logged context.
  """
  @spec can(Actor.t() | Scope.t(), String.t(), Resource.t() | nil, map()) :: Decision.t()
  def can(principal, capability, resource \\ nil, context \\ %{})

  def can(%Scope{} = scope, capability, resource, context)
      when is_binary(capability) and is_map(context) do
    case Scope.actor(scope) do
      %TenancyActor{type: :system, system_principal: name, company_id: company_id}
      when is_binary(name) ->
        decision =
          SystemPrincipalService.evaluate(
            scope,
            name,
            company_id,
            capability,
            resource,
            registry!()
          )

        :ok =
          DatabaseDecisionLogger.log_system_principal(
            name,
            company_id,
            capability,
            resource,
            decision,
            context
          )

        decision

      _person_or_nobody ->
        case scope_actor(scope) do
          {:ok, actor} -> can(actor, capability, resource, context)
          {:error, :no_authenticated_actor} -> Decision.deny(:denied_no_authenticated_actor)
        end
    end
  end

  def can(%Actor{} = actor, capability, resource, context)
      when is_binary(capability) and is_map(context) do
    decision = Evaluator.can(actor, capability, resource, context, registry!())
    :ok = DatabaseDecisionLogger.log(actor, capability, resource, decision, context)
    decision
  end

  @doc "Like `can/4`, but raises `AuthorizationDeniedError` unless allowed."
  @spec authorize!(Actor.t() | Scope.t(), String.t(), Resource.t() | nil, map()) :: :ok
  def authorize!(principal, capability, resource \\ nil, context \\ %{})

  def authorize!(principal, capability, resource, context)
      when is_struct(principal, Actor) or is_struct(principal, Scope) do
    case can(principal, capability, resource, context) do
      %Decision{allowed: true} -> :ok
      %Decision{} = decision -> raise AuthorizationDeniedError, decision: decision
    end
  end

  @doc """
  Effective allows, denies, and whether a grant-all role is in effect.

  `grant_all` is the boolean `EffectivePermissions.load/2` already computed.
  Callers that only need the allow list keep reading `:allowed`.
  """
  @spec effective_capabilities(Actor.t()) :: %{
          allowed: [String.t()],
          denied: [String.t()],
          grant_all: boolean()
        }
  def effective_capabilities(%Actor{} = actor) do
    registry = registry!()
    directory = directory!(registry)
    permissions = EffectivePermissions.load(actor, directory)

    %{
      allowed:
        permissions
        |> EffectivePermissions.allowed(registry.capabilities)
        |> then(fn allowed ->
          if Scope.platform_operator?(actor.scope) do
            allowed
          else
            allowed -- registry.platform_capabilities
          end
        end),
      denied: EffectivePermissions.denied(permissions),
      grant_all: permissions.grant_all
    }
  end

  @doc """
  Whether the authenticated actor holds a known capability through a direct
  allow or a role that names it. A `grant_all` role does not count, and a
  direct deny wins.
  """
  @spec explicitly_allowed?(Scope.t(), String.t()) :: boolean()
  def explicitly_allowed?(%Scope{} = scope, capability) when is_binary(capability) do
    registry = registry!()

    if capability in capabilities() and
         (capability not in registry.platform_capabilities or Scope.platform_operator?(scope)) do
      case scope_actor(scope) do
        {:ok, actor} ->
          EffectivePermissions.explicitly_allowed?(actor, capability, directory!(registry))

        {:error, :no_authenticated_actor} ->
          false
      end
    else
      false
    end
  end

  @spec list_roles(Scope.t()) :: [Bilimbi.Base.Authz.RoleSummary.t()]
  def list_roles(%Scope{} = scope), do: RoleService.list_roles(scope, registry!())

  @doc "Lists scoped roles through a bounded administration page."
  @spec list_roles(Scope.t(), keyword()) ::
          Bilimbi.Base.Authz.Page.t(Bilimbi.Base.Authz.RoleSummary.t())
  def list_roles(%Scope{} = scope, opts) when is_list(opts) do
    Administration.list_roles(scope, opts, registry!())
  end

  @doc "Fetches one scoped role with its capability keys and scoped principal assignments."
  @spec get_role(Scope.t(), pos_integer()) ::
          {:ok, Bilimbi.Base.Authz.RoleDetails.t()} | {:error, :not_found}
  def get_role(%Scope{} = scope, role_id), do: RoleService.get_role(scope, role_id, registry!())

  @doc """
  Grant flag and capability keys for many roles the scope may see, in one query.

  A role outside the scope is omitted. A visible role with no capability rows
  is present with an empty list. Use this when deciding which roles an actor
  may grant; `get_role/2` also loads every principal assignment and is one
  lookup per role.
  """
  @spec role_grants(Scope.t(), [pos_integer()]) :: %{
          pos_integer() => %{grant_all: boolean(), capabilities: [String.t()]}
        }
  def role_grants(%Scope{} = scope, role_ids) when is_list(role_ids) do
    RoleService.role_grants(scope, role_ids, registry!())
  end

  @doc """
  Companies the scope may own a custom role in, named for display.

  Role create needs a picker, and Belimbing builds one from
  `Company::query()->forTenant($tenantId)->orderBy('name')`. Base cannot query
  Core, so the naming half of the directory seam answers instead (#183, #264).
  """
  @spec companies_in_scope(Scope.t()) :: [Bilimbi.Base.Authz.CompanyDirectory.named_company()]
  def companies_in_scope(%Scope{} = scope) do
    directory = directory!(registry!())
    directory.companies_in_scope(scope)
  end

  @spec create_role(Scope.t(), pos_integer(), map()) ::
          {:ok, Bilimbi.Base.Authz.RoleSummary.t()}
          | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_role(%Scope{} = scope, company_id, attributes) do
    RoleService.create_role(scope, company_id, attributes, registry!())
  end

  @doc "Updates a custom role; system roles and cross-scope companies are rejected."
  @spec update_role(Scope.t(), pos_integer(), map()) ::
          {:ok, Bilimbi.Base.Authz.RoleSummary.t()}
          | {:error,
             :role_not_found
             | :system_role
             | :company_not_found
             | :role_has_principals
             | :invalid_company_id
             | Ecto.Changeset.t()}
  def update_role(%Scope{} = scope, role_id, attributes) when is_map(attributes) do
    RoleService.update_role(scope, role_id, attributes, registry!())
  end

  @doc "Deletes a custom role and intentionally database-cascades its grants and assignments."
  @spec delete_role(Scope.t(), pos_integer()) ::
          {:ok, :deleted} | {:error, :role_not_found | :system_role | Ecto.Changeset.t()}
  def delete_role(%Scope{} = scope, role_id) do
    RoleService.delete_role(scope, role_id, registry!())
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

  @doc "Removes one scoped principal-role assignment by its durable assignment ID."
  @spec unassign_role(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, :unassigned | :not_found} | {:error, :role_not_found}
  def unassign_role(%Scope{} = scope, role_id, assignment_id) do
    RoleService.unassign_role(scope, role_id, assignment_id, registry!())
  end

  @doc """
  Lists scoped principal-role assignments through a bounded page.

  This is the tenant-wide Principal Roles index. For one principal's assignments
  on a role or user screen, use `list_principal_role_assignments/4`.
  """
  @spec list_principal_roles(Scope.t(), keyword()) ::
          Bilimbi.Base.Authz.Page.t(Bilimbi.Base.Authz.PrincipalRoleSummary.t())
  def list_principal_roles(%Scope{} = scope, opts \\ []) when is_list(opts) do
    Administration.list_principal_roles(scope, opts, registry!())
  end

  @doc "Lists one principal's visible role assignments through a bounded page."
  @spec list_principal_role_assignments(Scope.t(), :user | :agent, pos_integer(), keyword()) ::
          Bilimbi.Base.Authz.Page.t(Bilimbi.Base.Authz.PrincipalRoleSummary.t())
  def list_principal_role_assignments(
        %Scope{} = scope,
        principal_type,
        principal_id,
        opts \\ []
      )
      when is_list(opts) do
    Administration.list_principal_role_assignments(
      scope,
      principal_type,
      principal_id,
      opts,
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

  @doc "Removes one visible persisted direct capability by its durable grant ID."
  @spec remove_principal_capability(
          Scope.t(),
          pos_integer()
        ) :: {:ok, :removed | :not_found}
  def remove_principal_capability(%Scope{} = scope, grant_id) do
    RoleService.remove_principal_capability(scope, grant_id, registry!())
  end

  @doc "Lists scoped direct principal capabilities through a bounded page, optionally for one principal."
  @spec list_principal_capabilities(Scope.t(), keyword()) ::
          Bilimbi.Base.Authz.Page.t(Bilimbi.Base.Authz.PrincipalCapabilitySummary.t())
  def list_principal_capabilities(%Scope{} = scope, opts \\ []) when is_list(opts) do
    Administration.list_principal_capabilities(scope, opts, registry!())
  end

  @doc "Lists scoped decision logs through a bounded payload-safe page."
  @spec list_decision_logs(Scope.t(), keyword()) ::
          Bilimbi.Base.Authz.Page.t(Bilimbi.Base.Authz.DecisionLogSummary.t())
  def list_decision_logs(%Scope{} = scope, opts \\ []) when is_list(opts) do
    Administration.list_decision_logs(scope, opts, registry!())
  end

  @doc """
  The system principals installed modules declare, with the capabilities
  each may be granted (ADR 0017).
  """
  @spec list_system_principals() :: [SystemPrincipals.principal()]
  def list_system_principals, do: SystemPrincipals.list()

  @doc """
  Lists the capabilities granted to system principals in the scope's companies.

  Option `:principal` limits the list to one name. The caller must be a user
  holding `admin.authz.system-principal.list`.
  """
  @spec list_system_capabilities(Scope.t(), keyword()) ::
          {:ok, [SystemPrincipalGrant.t()]} | {:error, :forbidden}
  def list_system_capabilities(%Scope{} = scope, opts \\ []) when is_list(opts) do
    with {:ok, _granter} <- administrator(scope, "admin.authz.system-principal.list") do
      {:ok, SystemPrincipalService.list(scope, opts, registry!())}
    end
  end

  @doc """
  Grants a declared capability to a system principal in one of the scope's companies.

  Grants are explicit: a principal holds nothing until an administrator
  grants it, per company, and only capabilities its module declared for it.
  The caller must be a signed-in user holding
  `admin.authz.system-principal.grant`; a system scope, named or not, is
  `:forbidden`, so a principal can never grant itself. The grant and an
  `authz.system_principal.granted` audit action naming the granter commit
  together. Granting an existing grant is `{:ok, :existing}` and records
  nothing.
  """
  @spec grant_system_capability(Scope.t(), pos_integer(), String.t(), String.t()) ::
          {:ok, :granted | :existing}
          | {:error,
             :forbidden
             | :undeclared_system_principal
             | :capability_not_declared
             | :company_not_found
             | :audit_unavailable
             | {:unknown_capabilities, [String.t()]}}
  def grant_system_capability(%Scope{} = scope, company_id, principal, capability) do
    with {:ok, granter} <- administrator(scope, "admin.authz.system-principal.grant") do
      SystemPrincipalService.grant(scope, company_id, principal, capability, granter, registry!())
    end
  end

  @doc """
  Revokes a system principal's capability in one of the scope's companies.

  The caller must be a signed-in user holding
  `admin.authz.system-principal.revoke`. The deletion and an
  `authz.system_principal.revoked` audit action naming who revoked it commit
  together. A grant that does not exist, or is outside the scope, is
  `{:ok, :not_found}`.
  """
  @spec revoke_system_capability(Scope.t(), pos_integer(), String.t(), String.t()) ::
          {:ok, :revoked | :not_found} | {:error, :forbidden | :audit_unavailable}
  def revoke_system_capability(%Scope{} = scope, company_id, principal, capability) do
    with {:ok, granter} <- administrator(scope, "admin.authz.system-principal.revoke") do
      SystemPrincipalService.revoke(
        scope,
        company_id,
        principal,
        capability,
        granter,
        registry!()
      )
    end
  end

  # Administering system principals is a person's act: the granter is the
  # sealed user on the scope, never an argument, and a system scope is refused.
  defp administrator(%Scope{} = scope, capability) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user} = actor ->
        if can(scope, capability).allowed do
          {:ok,
           %{
             actor_type: "user",
             actor_id: actor.user_id,
             company_id: actor.company_id,
             impersonator_id: actor.impersonator_id
           }}
        else
          {:error, :forbidden}
        end

      %TenancyActor{type: :system} ->
        {:error, :forbidden}
    end
  end

  @spec reconcile_system_roles(keyword()) ::
          {:ok, %{roles: non_neg_integer(), capabilities: non_neg_integer()}} | {:error, term()}
  def reconcile_system_roles(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    SystemRoleReconciler.reconcile(repo, registry!())
  end

  @doc """
  Lists persisted grants naming capabilities no installed module declares.

  Options: `:capabilities` (declared set, defaulting to the live registry),
  `:repo`, and `:prefix` for reading a named PostgreSQL schema. Comparison is
  case-sensitive, exactly like evaluation, so a stored case variant of a
  declared key is reported rather than excused.
  """
  @spec unknown_persisted_capabilities(keyword()) :: map()
  def unknown_persisted_capabilities(opts \\ []) when is_list(opts) do
    {capabilities, opts} = Keyword.pop_lazy(opts, :capabilities, fn -> capabilities() end)
    Diagnostics.unknown_persisted_capabilities(capabilities, opts)
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
