defmodule Bilimbi.Base.UI.Components.SortHeading do
  @moduledoc """
  The sort control of a column heading, shared by `table/1` in
  `Bilimbi.Base.UI.Components.Lists` and `flex_table/1` in
  `Bilimbi.Base.UI.Components.FlexTable`, so both tables sort with one
  button, one glyph and one `aria-sort` reading.

  It is a part of those two tables, not a component a page calls, so it is
  not in `Bilimbi.Base.UI.Components.modules/0` and `use
  Bilimbi.Base.UI.Components` does not import it.
  """
  use Phoenix.Component

  import Bilimbi.Base.UI.Components.Icon

  @doc "The button inside a sortable column heading: its label and the sort glyph."
  attr(:col, :map, required: true)
  attr(:table_id, :string, required: true)
  attr(:sort_by, :any, required: true)
  attr(:sort_dir, :any, required: true)
  attr(:sort_event, :any, default: "sort", doc: "an event name or a `JS` command")
  attr(:sort_target, :any, default: nil)

  def table_sort_heading(assigns) do
    ~H"""
    <button
      id={@col[:sort_id] || "#{@table_id}-sort-#{@col[:sort]}"}
      type="button"
      phx-click={@sort_event}
      phx-target={@sort_target}
      phx-value-sort={@col[:sort]}
      class={[
        "inline-flex items-center gap-1 rounded transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong/30",
        @col[:align] == :right && "ml-auto",
        @col[:align] != :right && "text-left"
      ]}
    >
      {@col[:label]}
      <.icon
        name={table_sort_icon(@col[:sort], @sort_by, @sort_dir)}
        class={["size-3.5", table_sort_active?(@col[:sort], @sort_by) && "text-action"]}
      />
    </button>
    """
  end

  @doc "The `aria-sort` value of a column heading; `nil` for a column that does not sort."
  def table_aria_sort(nil, _sort_by, _sort_dir), do: nil

  def table_aria_sort(sort, sort_by, sort_dir) do
    cond do
      not table_sort_active?(sort, sort_by) -> "none"
      table_sort_dir(sort_dir) == :asc -> "ascending"
      table_sort_dir(sort_dir) == :desc -> "descending"
      true -> "none"
    end
  end

  defp table_sort_icon(sort, sort_by, sort_dir) do
    cond do
      not table_sort_active?(sort, sort_by) -> "sort"
      table_sort_dir(sort_dir) == :asc -> "sort-asc"
      table_sort_dir(sort_dir) == :desc -> "sort-desc"
      true -> "sort"
    end
  end

  defp table_sort_active?(sort, sort_by), do: to_string(sort) == to_string(sort_by)

  defp table_sort_dir(dir) when dir in ["asc", :asc], do: :asc
  defp table_sort_dir(dir) when dir in ["desc", :desc], do: :desc
  defp table_sort_dir(_dir), do: nil
end
