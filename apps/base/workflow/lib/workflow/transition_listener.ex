defmodule Bilimbi.Base.Workflow.TransitionListener do
  @moduledoc """
  An owner's reaction to a committed status transition, delivered at least once.

  A listener never runs inside the transition. The transition writes a durable
  outbox row in its own transaction; delivery runs after that commit, once
  immediately and again from the Workflow maintenance schedule, until every
  listener registered for the subject returns `:ok`. A `{:error, reason}`, a
  raise or an exit defers the whole event with exponential backoff and the
  reason is kept on the row; it is delivered again later, to every listener.
  Make the effect idempotent on `event_key` (or `history_id`), as Belimbing's
  notification listener does with a deterministic notification id.

  `handle/2` receives the subject tenant's system scope, because nobody is
  signed in for a delivery, and plain event facts. The recorded actor is data
  about who performed the transition, never authority to act as them.

  The event map carries `event_key`, `event_type`, `subject` (`%{type, id}`),
  `flow`, `from_status`, `to_status`, `transition` (the stored edge columns),
  `history` (the stored history columns), `actor` (`%{type, id}`), `context`
  (`comment`, `comment_tag`, `assignees`, `attachments`, `metadata`),
  `transitioned_at` and `attempt`. Snapshot maps keep their JSON string keys.
  """
  alias Bilimbi.Base.Tenancy.Scope

  @callback handle(Scope.t(), map()) :: :ok | {:error, term()}
end
