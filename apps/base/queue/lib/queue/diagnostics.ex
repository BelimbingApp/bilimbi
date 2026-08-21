defmodule Bilimbi.Base.Queue.Diagnostics do
  @moduledoc "Bounded queue health aggregates without arguments or failure payloads."

  @enforce_keys [:available?, :backlog, :executing, :retryable, :discarded]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          available?: boolean(),
          backlog: non_neg_integer(),
          executing: non_neg_integer(),
          retryable: non_neg_integer(),
          discarded: non_neg_integer()
        }
end
