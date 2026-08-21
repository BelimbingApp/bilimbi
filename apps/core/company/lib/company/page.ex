defmodule Bilimbi.Core.Company.Page do
  @moduledoc "Public bounded result for tenant company administration lists."

  alias Bilimbi.Core.Company.IndexEntry

  @enforce_keys [:entries, :page, :page_size, :total_entries, :total_pages]
  defstruct [:entries, :page, :page_size, :total_entries, :total_pages]

  @type t :: %__MODULE__{
          entries: [IndexEntry.t()],
          page: pos_integer(),
          page_size: 25 | 50 | 100 | 300,
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
