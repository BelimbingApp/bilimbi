defmodule Bilimbi.Core.Employee.AdministrationPage do
  @moduledoc "Public bounded result for `Employee.list_administration_page/3`."

  alias Bilimbi.Core.Employee.AdministrationEntry

  @enforce_keys [:entries, :page, :page_size, :total_entries, :total_pages, :has_prev?, :has_next?]
  defstruct [:entries, :page, :page_size, :total_entries, :total_pages, :has_prev?, :has_next?]

  @type t :: %__MODULE__{
          entries: [AdministrationEntry.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer(),
          has_prev?: boolean(),
          has_next?: boolean()
        }
end
