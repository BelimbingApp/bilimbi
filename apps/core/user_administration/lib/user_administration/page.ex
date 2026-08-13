defmodule Bilimbi.Core.UserAdministration.Page do
  @moduledoc "A bounded, schema-free administration page."

  alias Bilimbi.Core.UserAdministration.Entry

  @enforce_keys [:entries, :page, :page_size, :total_entries, :total_pages]
  defstruct [:entries, :page, :page_size, :total_entries, :total_pages]

  @type t :: %__MODULE__{
          entries: [Entry.t()],
          page: pos_integer(),
          page_size: 10 | 25 | 50 | 100,
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
