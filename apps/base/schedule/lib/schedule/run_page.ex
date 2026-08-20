defmodule Bilimbi.Base.Schedule.RunPage do
  @moduledoc "Bounded database-backed page of redacted schedule history."

  alias Bilimbi.Base.Schedule.RunSummary

  @enforce_keys [:entries, :page, :page_size, :total_entries, :total_pages]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          entries: [RunSummary.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
