defmodule Bilimbi.Base.Queue.JobRef do
  @moduledoc "Stable result returned after a queue insertion."

  @enforce_keys [:id, :worker_id, :state, :conflict?]
  defstruct [:id, :worker_id, :state, :conflict?]

  @type t :: %__MODULE__{
          id: pos_integer(),
          worker_id: String.t(),
          state: atom(),
          conflict?: boolean()
        }
end
