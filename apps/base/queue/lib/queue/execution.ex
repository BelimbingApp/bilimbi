defmodule Bilimbi.Base.Queue.Execution do
  @moduledoc "Bounded execution facts passed to capability workers."

  @enforce_keys [:job_id, :attempt, :max_attempts, :queue]
  defstruct [:job_id, :attempt, :max_attempts, :queue]

  @type t :: %__MODULE__{
          job_id: pos_integer(),
          attempt: non_neg_integer(),
          max_attempts: pos_integer(),
          queue: String.t()
        }
end
