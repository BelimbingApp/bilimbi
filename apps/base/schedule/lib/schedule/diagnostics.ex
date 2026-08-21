defmodule Bilimbi.Base.Schedule.Diagnostics do
  @moduledoc "Independent scheduler, Queue, recorder, and due-work evidence."

  @enforce_keys [:scheduler, :queue, :recorder, :due_work]
  defstruct @enforce_keys

  @type availability :: :available | :unavailable
  @type due_work :: :due | :none_due | :unknown
  @type t :: %__MODULE__{
          scheduler: availability(),
          queue: availability(),
          recorder: availability(),
          due_work: due_work()
        }
end
