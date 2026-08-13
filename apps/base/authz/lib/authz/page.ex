defmodule Bilimbi.Base.Authz.Page do
  @moduledoc "Stable bounded-page result returned by Authz administration queries."

  @enforce_keys [:entries, :page, :page_size, :total_entries, :total_pages]
  defstruct [:entries, :page, :page_size, :total_entries, :total_pages]

  @type t(entry) :: %__MODULE__{
          entries: [entry],
          page: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
