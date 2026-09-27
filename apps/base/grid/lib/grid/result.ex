defmodule Bilimbi.Base.Grid.Result do
  @moduledoc """
  What one grid query returned: the rows of a window, how many rows the
  whole statement has, the value range of every numeric column across all
  of them (so a bar or a colour is scaled to the whole set, not the window
  a person happens to see), and the planner's cost estimate.
  """

  alias Bilimbi.Base.Grid.Column

  @enforce_keys [:columns, :rows, :total_entries, :offset, :limit]
  defstruct columns: [],
            rows: [],
            total_entries: 0,
            offset: 0,
            limit: 0,
            stats: %{},
            cost: nil

  @type row :: %{key: term(), cells: %{String.t() => term()}}

  @type t :: %__MODULE__{
          columns: [Column.t()],
          rows: [row()],
          total_entries: non_neg_integer(),
          offset: non_neg_integer(),
          limit: pos_integer(),
          stats: %{String.t() => %{min: term(), max: term()}},
          cost: float() | nil
        }

  @doc "The page shape `Bilimbi.Base.UI.Components.pagination/1` reads."
  @spec page(t()) :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer()
        }
  def page(%__MODULE__{} = result) do
    %{
      page: div(result.offset, result.limit) + 1,
      page_size: result.limit,
      total_entries: result.total_entries,
      total_pages: div(result.total_entries + result.limit - 1, result.limit)
    }
  end
end
