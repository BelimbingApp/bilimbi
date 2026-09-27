defmodule Bilimbi.Base.Tenancy.Authentication do
  @moduledoc """
  The edge seam that attaches an authenticated user to a scope.

  **This is not a domain API.** Domain code receives a scope and reads its
  actor with `Bilimbi.Base.Tenancy.Scope.actor/1`; it never calls this module.

  `sign_in/4` and `resume/2` are the two ways a scope gets a user actor, and
  `resume_system/2` is the one way it gets a named system principal. Each has
  exactly one caller:

    * `sign_in/4` — `BilimbiWeb.UserAuth`, after it has proven the durable
      session, the user, the company, and the tenant for this request or
      LiveView process. Nothing here re-checks those facts; the caller is the
      proof.
    * `resume/2` — `Bilimbi.Base.Queue.Worker`, when a job enqueued with
      `Bilimbi.Base.Queue.enqueue_for/3` runs. The job carries a token that
      `delegate/1` signed from a scope that already held the actor, and the
      installed `Bilimbi.Base.Tenancy.ActorVerifier` re-proves the user.
    * `resume_system/2` — `Bilimbi.Base.Queue.Worker`, when a job enqueued with
      `Bilimbi.Base.Queue.enqueue_as_system/4` runs. The token names the
      tenant, the company, and the principal its worker declared; the
      principal must still be declared by an installed module (ADR 0017).

  Elixir cannot make a public function private to one caller. The seal is the
  enforcement: an actor that did not come from here fails `Scope.actor/1`, and
  a module that called `sign_in/4` itself would be asserting an identity it
  had not proven. Adding a caller is an architecture change that review must
  justify against ADR 0016.
  """

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.ActorSeal
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals

  # A queued job may retry for days. A week bounds how long a delegated actor
  # outlives the request that issued it, and matches Base Queue's job pruning.
  @default_delegation_max_age 7 * 24 * 60 * 60

  @doc """
  Attaches the signed-in user to a freshly proven system scope.

  Options, given together or not at all:

    * `:impersonator_id` — the operator behind an impersonated session. The
      user is the account acted as; the impersonator is who acted.
    * `:impersonation_session_id` — the borrowed durable session, so work
      queued during it stops acting for the user once it ends.

  Raises `ArgumentError` when the scope already names a user or a system
  principal: an actor is set once, at the edge, and never changed. A system
  principal is never a user, so it can never be signed in as one or
  impersonated.
  """
  @spec sign_in(Scope.t(), pos_integer(), pos_integer(), keyword()) :: Scope.t()
  def sign_in(%Scope{tenant: tenant} = scope, user_id, company_id, opts \\ [])
      when is_list(opts) do
    case Scope.actor(scope) do
      %Actor{type: :system, system_principal: name} when is_binary(name) ->
        raise ArgumentError, "a scope's actor is set once; this scope runs as #{name}"

      %Actor{type: :system} ->
        actor =
          ActorSeal.user(
            tenant,
            user_id,
            company_id,
            Keyword.get(opts, :impersonator_id),
            Keyword.get(opts, :impersonation_session_id)
          )

        %Scope{tenant: tenant, actor: actor}

      %Actor{type: :user} ->
        raise ArgumentError, "a scope's actor is set once; this scope already names a user"
    end
  end

  @doc """
  Signs the scope's user actor for a background job that acts for them.

  The token carries only stable IDs and is useless without the actor secret.
  A system scope has no user to delegate. A job runs as a named system
  principal through `delegate_system/3` instead.
  """
  @spec delegate(Scope.t()) :: {:ok, binary()} | {:error, :no_authenticated_actor}
  def delegate(%Scope{} = scope) do
    case Scope.actor(scope) do
      %Actor{type: :user} = actor ->
        {:ok, ActorSeal.sign_delegation(Scope.tenant_id(scope), actor)}

      %Actor{type: :system} ->
        {:error, :no_authenticated_actor}
    end
  end

  @doc """
  Rebuilds the delegated scope from a `delegate/1` token and re-proves it.

  A tampered token is `:invalid`; one older than `:max_age` seconds (default
  one week) is `:expired`; a tenant that is gone or soft-deleted fails as
  `Bilimbi.Base.Tenancy.scope/1` does. The installed
  `Bilimbi.Base.Tenancy.ActorVerifier` then re-proves the user:
  `:actor_refused` when it does not, `:no_actor_verifier` when no installed
  module contributes one. Whether the user may still perform the job's
  operation is decided when it runs, by Base Authz against live grants.
  """
  @spec resume(binary(), keyword()) ::
          {:ok, Scope.t()}
          | {:error,
             :invalid
             | :expired
             | :not_found
             | :soft_deleted
             | :actor_refused
             | :no_actor_verifier}
  def resume(token, opts \\ []) when is_binary(token) and is_list(opts) do
    max_age = Keyword.get(opts, :max_age, @default_delegation_max_age)

    with {:ok, {tenant_id, user_id, company_id, impersonator_id, session_id}} <-
           ActorSeal.verify_delegation(token, max_age),
         {:ok, tenant_scope} <- Tenancy.scope(tenant_id),
         scope =
           sign_in(tenant_scope, user_id, company_id,
             impersonator_id: impersonator_id,
             impersonation_session_id: session_id
           ),
         :ok <- verify_actor(scope) do
      {:ok, scope}
    end
  end

  @doc """
  Signs a job's run as the declared system principal `name` in `company_id`.

  Only the scope's tenant is taken from `scope`: the job does not act for
  whoever enqueued it. `Bilimbi.Base.Queue.enqueue_as_system/4` is the caller,
  after checking that its worker belongs to the module that declared `name`.
  An undeclared name is refused.
  """
  @spec delegate_system(Scope.t(), String.t(), pos_integer()) ::
          {:ok, binary()} | {:error, :undeclared_system_principal | :invalid_company}
  def delegate_system(%Scope{} = scope, name, company_id) do
    cond do
      not SystemPrincipals.declared?(name) ->
        {:error, :undeclared_system_principal}

      not (is_integer(company_id) and company_id > 0) ->
        {:error, :invalid_company}

      true ->
        {:ok, ActorSeal.sign_system_delegation(Scope.tenant_id(scope), name, company_id)}
    end
  end

  @doc """
  Rebuilds a system principal's scope from a `delegate_system/3` token.

  A tampered token is `:invalid` and one older than `:max_age` seconds
  (default one week) is `:expired`; a tenant that is gone or soft-deleted
  fails as `Bilimbi.Base.Tenancy.scope/1` does; a principal no installed
  module declares any longer is `:undeclared_system_principal`. The scope's
  actor holds no capability by itself: Base Authz answers from the grants an
  administrator gave that principal in that company.
  """
  @spec resume_system(binary(), keyword()) ::
          {:ok, Scope.t()}
          | {:error,
             :invalid | :expired | :not_found | :soft_deleted | :undeclared_system_principal}
  def resume_system(token, opts \\ []) when is_binary(token) and is_list(opts) do
    max_age = Keyword.get(opts, :max_age, @default_delegation_max_age)

    with {:ok, {tenant_id, name, company_id}} <-
           ActorSeal.verify_system_delegation(token, max_age),
         {:ok, %Scope{tenant: tenant}} <- Tenancy.scope(tenant_id),
         {:ok, _principal} <- SystemPrincipals.fetch(name) do
      {:ok, %Scope{tenant: tenant, actor: ActorSeal.system_principal(tenant, name, company_id)}}
    end
  end

  defp verify_actor(scope) do
    case ContributionRegistry.consumer!(:actor_verifier) do
      nil ->
        {:error, :no_actor_verifier}

      verifier ->
        if verifier.verify_actor(scope) == :ok, do: :ok, else: {:error, :actor_refused}
    end
  end
end
