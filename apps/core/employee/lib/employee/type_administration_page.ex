defmodule Bilimbi.Core.Employee.TypeAdministrationPage do
  @moduledoc "Public bounded result for `Employee.list_type_administration_page/3`."

  alias Bilimbi.Core.Employee.TypeAdministrationEntry

  @enforce_keys [
    :entries,
    :page,
    :page_size,
    :total_entries,
    :total_pages,
    :has_prev?,
    :has_next?
  ]
  defstruct [:entries, :page, :page_size, :total_entries, :total_pages, :has_prev?, :has_next?]

  @type t :: %__MODULE__{
          entries: [TypeAdministrationEntry.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer(),
          has_prev?: boolean(),
          has_next?: boolean()
        }
end
