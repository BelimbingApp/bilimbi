defmodule Bilimbi.Base.Queue.JobSummary do
  @moduledoc "Redacted operator-facing queue job summary."

  @enforce_keys [
    :id,
    :worker_id,
    :queue,
    :state,
    :attempt,
    :max_attempts,
    :available?,
    :inserted_at,
    :scheduled_at,
    :completed_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: pos_integer(),
          worker_id: String.t(),
          queue: String.t(),
          state: atom(),
          attempt: non_neg_integer(),
          max_attempts: pos_integer(),
          available?: boolean(),
          inserted_at: DateTime.t(),
          scheduled_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }
end
