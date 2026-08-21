defmodule Bilimbi.Base.Queue.JobPage do
  @moduledoc "Bounded page of redacted queue job summaries."

  @enforce_keys [:entries, :page, :page_size, :total]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          entries: [Bilimbi.Base.Queue.JobSummary.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer()
        }
end
