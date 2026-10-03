defmodule Bilimbi.Base.Workflow do
  @moduledoc """
  Tenant-scoped status transitions, durable processes and compatible history.

  Subjects are `%{type: stable_key, id: bigint_or_decimal_string}`. Installed
  owners contribute definitions and adapters through `:workflow`; callers
  receive plain maps. Actor and tenant authority come only from Scope.

  Transitions lock and reread the subject, check the persisted active edge,
  capability and owner guard, then commit owner status/action, history and
  semantic Audit fact together. Every refusal rolls back database effects.
  Context carries comment, comment_tag, assignees, attachments, metadata and
  owner input; it cannot name an actor or tenant. Anonymous system writes fail.
  Named system principals remain subject to owner policy and Authz.
  """
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.{Coordination, Definitions, Engine, PendingWork}

  @type subject_ref :: %{type: String.t(), id: pos_integer() | String.t()}
  @spec transition(Scope.t(), subject_ref(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def transition(%Scope{} = scope, subject, to, context \\ %{}) when is_binary(to),
    do: Engine.transition(scope, subject, to, context)

  @doc "Lists capability-permitted active edges. Execution rechecks owner policy and contextual guards."
  @spec available_transitions(Scope.t(), subject_ref()) :: {:ok, [map()]} | {:error, term()}
  def available_transitions(%Scope{} = scope, subject), do: Engine.available(scope, subject)

  @spec record_initial(Scope.t(), subject_ref(), map()) :: {:ok, map()} | {:error, term()}
  def record_initial(%Scope{} = scope, subject, context \\ %{}),
    do: Engine.record(scope, subject, :record_initial, context)

  @spec record_comment(Scope.t(), subject_ref(), map()) :: {:ok, map()} | {:error, term()}
  def record_comment(%Scope{} = scope, subject, context),
    do: Engine.record(scope, subject, :record_comment, context)

  @doc """
  Binds retained source history after the installed owner proves a locked
  subject and authorizes adoption. No history or legacy configuration is
  rewritten. Conflicting ownership fails; repeated identical proof is safe.
  """
  @spec adopt_subject(Scope.t(), subject_ref()) :: {:ok, map()} | {:error, term()}
  def adopt_subject(%Scope{} = scope, subject), do: Engine.adopt(scope, subject)

  @doc "Reads a bounded timeline ordered by transitioned_at then id; pass next_cursor as :after."
  @spec history(Scope.t(), subject_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def history(%Scope{} = scope, subject, opts \\ []), do: Engine.history(scope, subject, opts)

  @doc """
  Explicit insert-only initialization from installed definitions, for owner
  production seed callbacks. Existing rows always win, including inactive
  configuration and legacy class strings. Never called at boot or adoption.
  """
  @spec seed_definitions() :: {:ok, :seeded} | {:error, term()}
  def seed_definitions, do: Definitions.seed()

  @doc "Starts an owner-proven process; :idempotency_key is required. Versions are immutable."
  @spec start_run(Scope.t(), String.t(), subject_ref(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_run(%Scope{} = scope, definition, subject, opts),
    do: Coordination.start(scope, definition, subject, opts)

  @doc "Reads the proven run and its bounded materialized graph without exposing Ecto schemas or lease tokens."
  @spec get_run(Scope.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def get_run(%Scope{} = scope, run_id), do: Coordination.get(scope, run_id)

  @doc "Completes due available work with the expected version and executor; accepts an item ID or %{step_key: key}."
  @spec complete_work(Scope.t(), pos_integer(), pos_integer() | map(), map()) ::
          {:ok, map()} | {:error, term()}
  def complete_work(%Scope{} = scope, run_id, item, request),
    do: Coordination.complete(scope, run_id, item, request)

  @doc "Blocks unfinished work and emits process.superseded; refuses live worker leases."
  @spec supersede_run(Scope.t(), pos_integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def supersede_run(%Scope{} = scope, run_id, reason),
    do: Coordination.supersede(scope, run_id, reason)

  @doc "Recovers expired leases and releases dependencies/timers on the existing graph. Paused and terminal runs are retained."
  @spec reconcile_run(Scope.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def reconcile_run(%Scope{} = scope, run_id), do: Coordination.reconcile(scope, run_id)

  @doc "Records an idempotent external fact, releasing matching signal gates. Same key with different content conflicts."
  @spec signal_run(Scope.t(), pos_integer(), String.t(), term(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def signal_run(%Scope{} = scope, run_id, name, payload, idempotency_key),
    do: Coordination.signal(scope, run_id, name, payload, idempotency_key)

  @doc "Bounded due work ordered by item priority descending, availability and ID. Cursor advances over scanned candidates."
  @spec pending_work(Scope.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def pending_work(%Scope{} = scope, opts \\ []), do: PendingWork.list(scope, opts)

  @doc "Bounded retained process event facts, ordered by run sequence; :after is the last sequence."
  @spec run_events(Scope.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_events(%Scope{} = scope, run_id, opts \\ []),
    do: Coordination.events(scope, run_id, opts)
end
