defmodule Bilimbi.Base.Audit.Context do
  @moduledoc """
  Per-process actor/request context for captured mutations (ADR 0013).

  The port of Belimbing's `RequestContext`: the web edge resolves it once
  per HTTP request or LiveView process — the same lifecycle as the locale —
  and capture reads it when shaping rows. Absent context is explicitly `unknown/0`, never an assertion that the
  caller was a guest. `with_scope/2` derives identity from the sealed scope
  for direct facade calls and background work, restoring context afterwards.

  `impersonator_id` names the operator behind an impersonated session. The
  actor pair keeps naming the account acted as; the impersonator is the
  person who actually acted. Nil outside impersonation.

  `system_principal` names the declared system identity a job runs as, such
  as `coating.line_import`, with `actor_type` `"system"` and `actor_id` `0`: the
  work is attributed to that identity, never to a user (ADR 0017). Base Queue
  sets it for a job enqueued with `Bilimbi.Base.Queue.enqueue_as_system/4`.

  This is presentation-of-actor state, not authorization: nothing reads it
  to decide anything, only to record who did what.
  """

  @key __MODULE__

  defstruct actor_type: "unknown",
            actor_id: 0,
            actor_role: nil,
            impersonator_id: nil,
            system_principal: nil,
            company_id: nil,
            tenant_id: nil,
            ip_address: nil,
            url: nil,
            user_agent: nil,
            trace_id: nil

  @type t :: %__MODULE__{
          actor_type: String.t(),
          actor_id: non_neg_integer(),
          actor_role: String.t() | nil,
          impersonator_id: pos_integer() | nil,
          system_principal: String.t() | nil,
          company_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil,
          ip_address: String.t() | nil,
          url: String.t() | nil,
          user_agent: String.t() | nil,
          trace_id: String.t() | nil
        }

  @spec put(t() | nil) :: :ok
  def put(nil) do
    Process.delete(@key)
    :ok
  end

  def put(%__MODULE__{} = context) do
    Process.put(@key, context)
    :ok
  end

  @doc "The process context, or unknown attribution when none was set."
  @spec get() :: t()
  def get, do: Process.get(@key) || %__MODULE__{}
  @doc "Derives attribution from a verified scope, preserving request diagnostics."
  def from_scope(%Bilimbi.Base.Tenancy.Scope{} = scope) do
    actor = Bilimbi.Base.Tenancy.Scope.actor(scope)

    %{
      get()
      | actor_type: if(actor.type == :user, do: "user", else: "system"),
        actor_id: actor.user_id || 0,
        company_id: actor.company_id,
        tenant_id: Bilimbi.Base.Tenancy.Scope.tenant_id(scope),
        impersonator_id: actor.impersonator_id,
        system_principal: actor.system_principal
    }
  end

  @system_actor_types ~w(console queue scheduler system)

  @doc """
  Runs work attributed to a named non-user actor — `"system"` for seeds and
  tasks, `"scheduler"`, `"queue"`, or `"console"` — restoring prior context
  even on failure.
  """
  @spec with_actor(String.t(), (-> result)) :: result when result: var
  def with_actor(actor_type, fun)
      when actor_type in @system_actor_types and is_function(fun, 0) do
    previous = Process.get(@key)
    put(%{get() | actor_type: actor_type, actor_id: 0})

    try do
      fun.()
    after
      put(previous)
    end
  end

  @doc "Runs work attributed to the scope, restoring prior context even on failure."
  def with_scope(scope, fun) when is_function(fun, 0) do
    context = from_scope(scope)
    previous = Process.get(@key)
    put(context)

    try do
      fun.()
    after
      put(previous)
    end
  end
end
