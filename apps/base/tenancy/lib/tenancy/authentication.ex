defmodule Bilimbi.Base.Tenancy.Authentication do
  @moduledoc """
  The edge seam that attaches an authenticated user to a scope.

  **This is not a domain API.** Domain code receives a scope and reads its
  actor with `Bilimbi.Base.Tenancy.Scope.actor/1`; it never calls this module.

  `sign_in/4` and `resume/2` are the two ways a scope gets a user actor, and
  each has exactly one caller:

    * `sign_in/4` — `BilimbiWeb.UserAuth`, after it has proven the durable
      session, the user, the company, and the tenant for this request or
      LiveView process. Nothing here re-checks those facts; the caller is the
      proof.
    * `resume/2` — `Bilimbi.Base.Queue.Worker`, when a job enqueued with
      `Bilimbi.Base.Queue.enqueue_for/3` runs. The job carries a token that
      `delegate/1` signed from a scope that already held the actor.

  Elixir cannot make a public function private to one caller, so the fence is
  checked instead: `apps/web/test/bilimbi_web/scope_actor_boundary_test.exs`
  reads every compiled Bilimbi module's remote calls and fails on any other
  caller. Adding one is an architecture change: say why in the test's
  allowlist and in review.
  """

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.ActorSeal
  alias Bilimbi.Base.Tenancy.Scope

  # A queued job may retry for days. A week bounds how long a delegated actor
  # outlives the request that issued it, and matches Base Queue's job pruning.
  @default_delegation_max_age 7 * 24 * 60 * 60

  @doc """
  Attaches the signed-in user to a freshly proven system scope.

  Options:

    * `:impersonator_id` — the operator behind an impersonated session. The
      user is the account acted as; the impersonator is who acted.

  Raises `ArgumentError` when the scope already names a user: an actor is set
  once, at the edge, and never changed.
  """
  @spec sign_in(Scope.t(), pos_integer(), pos_integer(), keyword()) :: Scope.t()
  def sign_in(%Scope{tenant: tenant} = scope, user_id, company_id, opts \\ [])
      when is_list(opts) do
    case Scope.actor(scope) do
      %Actor{type: :system} ->
        actor = ActorSeal.user(tenant, user_id, company_id, Keyword.get(opts, :impersonator_id))
        %Scope{tenant: tenant, actor: actor}

      %Actor{type: :user} ->
        raise ArgumentError, "a scope's actor is set once; this scope already names a user"
    end
  end

  @doc """
  Signs the scope's user actor for a background job that acts for them.

  The token carries only stable IDs and is useless without the actor secret.
  A system scope has no user to delegate.
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
  Rebuilds the delegated scope from a `delegate/1` token, re-proving the tenant.

  A tampered token is `:invalid`; one older than `:max_age` seconds (default
  one week) is `:expired`; a tenant that is gone or soft-deleted fails as
  `Bilimbi.Base.Tenancy.scope/1` does. Whether the user may still perform the
  job's operation is decided when it runs, by Base Authz against live grants.
  """
  @spec resume(binary(), keyword()) ::
          {:ok, Scope.t()} | {:error, :invalid | :expired | :not_found | :soft_deleted}
  def resume(token, opts \\ []) when is_binary(token) and is_list(opts) do
    max_age = Keyword.get(opts, :max_age, @default_delegation_max_age)

    with {:ok, {tenant_id, user_id, company_id, impersonator_id}} <-
           ActorSeal.verify_delegation(token, max_age),
         {:ok, scope} <- Tenancy.scope(tenant_id) do
      {:ok, sign_in(scope, user_id, company_id, impersonator_id: impersonator_id)}
    end
  end
end
