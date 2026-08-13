defmodule Bilimbi.Core.Geonames.Web.Components do
  @moduledoc false

  use Bilimbi.Base.UI, :html

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :sort, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :string, required: true
  attr :align, :atom, values: [:left, :right], default: :left

  def sortable_heading(assigns) do
    ~H"""
    <th
      scope="col"
      class={[
        "px-4 py-2.5 text-xs font-semibold uppercase tracking-wider text-ink-subtle",
        @align == :right && "text-right"
      ]}
    >
      <button
        id={@id}
        type="button"
        phx-click="sort"
        phx-value-sort={@sort}
        class={[
          "inline-flex items-center gap-1 rounded text-left transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25",
          @align == :right && "ml-auto"
        ]}
      >
        {@label}
        <.icon
          name={sort_icon(@sort, @sort_by, @sort_dir)}
          class={[
            "size-3.5",
            @sort == @sort_by && "text-action"
          ]}
        />
      </button>
    </th>
    """
  end

  attr :id, :string, required: true
  attr :page, :any, required: true

  def pagination(assigns) do
    ~H"""
    <nav id={@id} aria-label="Pagination" class="flex items-center justify-between gap-3 border-t border-line-subtle px-4 py-3">
      <p id={"#{@id}-summary"} class="text-xs text-ink-subtle">
        {page_summary(@page)}
      </p>
      <div class="flex items-center gap-2">
        <button
          id={"#{@id}-previous"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page - 1}
          disabled={@page.page <= 1}
          class="rounded-md border border-line bg-surface px-2.5 py-1.5 text-xs font-medium text-ink transition hover:bg-surface-sunken disabled:cursor-not-allowed disabled:opacity-50"
        >
          Previous
        </button>
        <span id={"#{@id}-position"} class="text-xs tabular-nums text-ink-muted">
          {page_position(@page)}
        </span>
        <button
          id={"#{@id}-next"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page + 1}
          disabled={@page.page >= @page.total_pages or @page.total_pages == 0}
          class="rounded-md border border-line bg-surface px-2.5 py-1.5 text-xs font-medium text-ink transition hover:bg-surface-sunken disabled:cursor-not-allowed disabled:opacity-50"
        >
          Next
        </button>
      </div>
    </nav>
    """
  end

  def format_integer(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  def format_integer(_value), do: "—"

  def format_date(%NaiveDateTime{} = value), do: value |> NaiveDateTime.to_date() |> Date.to_iso8601()
  def format_date(_value), do: "—"

  defp sort_icon(sort, sort, "asc"), do: "hero-chevron-up"
  defp sort_icon(sort, sort, "desc"), do: "hero-chevron-down"
  defp sort_icon(_sort, _sort_by, _sort_dir), do: "hero-chevron-up-down"

  defp page_summary(%{total_entries: 0}), do: "No results"

  defp page_summary(%{page: page, page_size: page_size, total_entries: total_entries}) do
    first = (page - 1) * page_size + 1
    last = min(page * page_size, total_entries)
    "Showing #{first}–#{last} of #{total_entries}"
  end

  defp page_position(%{total_pages: 0}), do: "Page 0 of 0"
  defp page_position(%{page: page, total_pages: total_pages}), do: "Page #{page} of #{total_pages}"
end
