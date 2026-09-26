defmodule Bilimbi.Base.Queue.Execution do
  @moduledoc """
  Bounded execution facts passed to capability workers.

  `scope` is the signed-in user's scope for a job enqueued with
  `Bilimbi.Base.Queue.enqueue_for/3`, rebuilt when the job runs with its
  tenant and user re-proven live. It is `nil` for ordinary system work; such a worker
  builds a system scope with `Bilimbi.Base.Tenancy.scope/1` when it needs one.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @enforce_keys [:job_id, :attempt, :max_attempts, :queue]
  defstruct [:job_id, :attempt, :max_attempts, :queue, scope: nil]

  @type t :: %__MODULE__{
          job_id: pos_integer(),
          attempt: non_neg_integer(),
          max_attempts: pos_integer(),
          queue: String.t(),
          scope: Scope.t() | nil
        }
end
