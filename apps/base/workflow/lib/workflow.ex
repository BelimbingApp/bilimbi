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

  Human actions are registered owner contributions a signed-in person
  executes once: the gate binds the actor's capability, the proven subject
  and any bound work item, enforces the expected subject and work versions,
  and keeps one result per tenant and idempotency key with an intent digest.
  """
  alias Bilimbi.Base.Tenancy.Scope

  alias Bilimbi.Base.Workflow.{
    Coordination,
    Definitions,
    Engine,
    HumanActionGate,
    PendingWork,
    TransitionOutbox
  }

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

  @doc "Pauses a running run with a reason. Paused runs keep their work state and release nothing until resumed."
  @spec pause_run(Scope.t(), pos_integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def pause_run(%Scope{} = scope, run_id, reason), do: Coordination.pause(scope, run_id, reason)

  @doc "Resumes a paused run and reconciles its saved graph. Resuming a running run is a no-op."
  @spec resume_run(Scope.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def resume_run(%Scope{} = scope, run_id), do: Coordination.resume(scope, run_id)

  @doc """
  Leases one due work item to `worker`, returning `{:ok, nil}` when none is claimable.

  Options are `:lease_seconds` (default 300), `:definition_key`, `:executor_keys`
  and `:run_ids`. The result carries `claim: %{run_id, work_item_id, lease_token}`;
  every worker-owned call needs that claim, so a late worker cannot overwrite a
  reassignment.
  """
  @spec claim_work(Scope.t(), String.t(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def claim_work(%Scope{} = scope, worker, opts \\ []),
    do: Coordination.claim(scope, worker, opts)

  @doc "Extends the caller's live lease by `lease_seconds` from now."
  @spec heartbeat_work(Scope.t(), map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def heartbeat_work(%Scope{} = scope, claim, lease_seconds \\ 300),
    do: Coordination.heartbeat(scope, claim, lease_seconds)

  @doc "Completes leased work with `%{outcome: ..., output: ..., result_ref: ...}`. A terminal item is returned unchanged."
  @spec complete_claimed_work(Scope.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def complete_claimed_work(%Scope{} = scope, claim, request),
    do: Coordination.complete_claimed(scope, claim, request)

  @doc """
  Fails leased work. Retryable failures with attempts remaining return to pending
  at `:retry_at` (default now); others fail the item. Options are `:retry_at`,
  `:retryable` (default true) and `:failure_category` (default "unclassified").
  """
  @spec fail_work(Scope.t(), map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fail_work(%Scope{} = scope, claim, error, opts \\ []),
    do: Coordination.fail(scope, claim, error, opts)

  @doc "Blocks leased work with a reason, keeping the worker's `:output` and `:result_ref`."
  @spec block_claimed_work(Scope.t(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def block_claimed_work(%Scope{} = scope, claim, reason, opts \\ []),
    do: Coordination.block_claimed(scope, claim, reason, opts)

  @doc "Administratively waives unfinished work with a reason and outcome (default \"waived\")."
  @spec waive_work(Scope.t(), pos_integer(), pos_integer() | map(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def waive_work(%Scope{} = scope, run_id, item, reason, outcome \\ "waived"),
    do: Coordination.waive(scope, run_id, item, reason, outcome)

  @doc "Administratively blocks unfinished work with a reason."
  @spec block_work(Scope.t(), pos_integer(), pos_integer() | map(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def block_work(%Scope{} = scope, run_id, item, reason),
    do: Coordination.block(scope, run_id, item, reason)

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

  @doc """
  Delivers due transition events from the durable outbox, at most `:limit`
  (default 100) rows in id order, and returns `%{delivered, deferred, skipped}`.

  Installation-wide maintenance, not a tenant's read: each event is
  delivered under its own subject's tenant scope, resolved from the proven
  subject binding. The maintenance schedule calls this every minute; call it
  to drain a backlog or when that definition is not yet reviewed.
  """
  @spec deliver_transition_events(keyword()) :: {:ok, map()}
  def deliver_transition_events(opts \\ []), do: TransitionOutbox.deliver_due(opts)

  @doc """
  Locks and settles every running, tenant-scoped process run of every live
  tenant, up to `:limit` (default 500) per tenant, and returns
  `%{reconciled, skipped}`. Expired leases are repaired and due timers and
  satisfied dependencies released on the saved graph, as `reconcile_run/2`
  does for one run. Owner `:reconcile` authority is not asked: this is Base's
  own lease hygiene under each tenant's system scope, and a run whose
  definition, subject or tenant cannot be proved is skipped unchanged.
  """
  @spec reconcile_running_runs(keyword()) :: {:ok, map()}
  def reconcile_running_runs(opts \\ []), do: Coordination.sweep(opts)

  @doc "Bounded retained process event facts, ordered by run sequence; :after is the last sequence."
  @spec run_events(Scope.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_events(%Scope{} = scope, run_id, opts \\ []),
    do: Coordination.events(scope, run_id, opts)

  @doc """
  Lists the human actions the signed-in actor may execute on a subject.

  Returns `%{subject_version: token, actions: entries}`. Each entry carries
  the action's `key`, `label`, `capability` and `executor_key`; a work-bound
  action appears once per due available work item with `process_run_id`,
  `work_item_id` and `work_version`. A page echoes the tokens back through
  `execute_action/3`. Availability is not business eligibility: execution
  repeats every check under the subject lock.
  """
  @spec available_actions(Scope.t(), subject_ref()) :: {:ok, map()} | {:error, term()}
  def available_actions(%Scope{} = scope, subject),
    do: HumanActionGate.available(scope, subject)

  @doc """
  Executes one human action exactly once per tenant and idempotency key.

  The request map carries `:action_key`, `:idempotency_key`,
  `:expected_subject_version`, an optional JSON `:payload` and, for a
  work-bound action, `:process_run_id`, `:work_item_id` and
  `:expected_work_version`. A repeated request with the same intent returns
  the saved result with `replayed: true`; the same key with different intent
  conflicts. A stale subject or work version, a missing capability, another
  tenant or a system actor refuses, and every refusal rolls back the owner
  handler, the request row and the work completion together.
  """
  @spec execute_action(Scope.t(), subject_ref(), map()) :: {:ok, map()} | {:error, term()}
  def execute_action(%Scope{} = scope, subject, request),
    do: HumanActionGate.execute(scope, subject, request)
end
