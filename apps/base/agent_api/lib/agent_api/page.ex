defmodule Bilimbi.Base.AgentApi.Page do
  @moduledoc """
  One page of a list operation's result.

  A handler wraps its facade's bounded page in this struct so every list
  operation answers in one shape: the entries are the result, and the page
  facts travel beside them as `meta.page`.
  """

  @enforce_keys [:entries, :page, :page_size, :total]
  defstruct [:entries, :page, :page_size, :total]

  @type t :: %__MODULE__{
          entries: [term()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer()
        }
end
