defmodule Bilimbi.Core.Employee.HrHandoffPage do
  @moduledoc """
  One page of `Bilimbi.Core.Employee.hr_handoff_page/3`.

  `next_cursor` is the cursor for the following page, or `nil` after the
  last one.
  """

  alias Bilimbi.Core.Employee.HrHandoffEntry

  @enforce_keys [:entries, :next_cursor]
  defstruct [:entries, :next_cursor]

  @type t :: %__MODULE__{
          entries: [HrHandoffEntry.t()],
          next_cursor: pos_integer() | nil
        }
end
