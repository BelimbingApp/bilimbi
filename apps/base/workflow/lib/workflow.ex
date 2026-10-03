defmodule Bilimbi.Base.Workflow do
  @moduledoc """
  Tenant-scoped status transitions and compatible history.

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
  alias Bilimbi.Base.Workflow.{Definitions, Engine}

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
end
