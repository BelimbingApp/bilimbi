defmodule Bilimbi.Core.Geonames.Web.Components do
  @moduledoc false

  use Bilimbi.Base.UI, :html

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:sort, :string, required: true)
  attr(:sort_by, :string, required: true)
  attr(:sort_dir, :string, required: true)
  attr(:align, :atom, values: [:left, :right], default: :left)

  def sortable_heading(assigns) do
    ~H"""
    <th
      scope="col"
      aria-sort={sort_aria(@sort, @sort_by, @sort_dir)}
      class={[
        "px-2 py-1.5 text-[0.6875rem] font-medium tracking-wide text-ink-subtle",
        @align == :right && "text-right"
      ]}
    >
      <button
        id={@id}
        type="button"
        phx-click="sort"
        phx-value-sort={@sort}
        title={"Sort by #{@label}"}
        class={[
          "inline-flex items-center gap-1 rounded text-left transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25",
          @align == :right && "ml-auto"
        ]}
      >
        {@label}
        <.icon
          name={sort_icon(@sort, @sort_by, @sort_dir)}
          class={[
            "size-3 shrink-0",
            @sort == @sort_by && "text-brand-strong"
          ]}
        />
      </button>
    </th>
    """
  end

  attr(:id, :string, required: true)
  attr(:page, :any, required: true)
  attr(:page_sizes, :list, required: true)
  attr(:filters_form, :any, required: true)

  def pagination(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Pagination"
      class="flex flex-col gap-2 border-t border-line-subtle px-2 py-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <p id={"#{@id}-summary"} class="text-xs text-ink-muted">
          {page_summary(@page)}
        </p>
        <.form
          id={"#{@id}-page-size-form"}
          for={@filters_form}
          phx-change="filters"
          class="flex items-center gap-1.5"
        >
          <span class="text-xs text-ink-muted">Rows per page</span>
          <.input
            id={"#{@id}-page-size"}
            type="select"
            field={@filters_form[:perPage]}
            label="Rows per page"
            label_class="sr-only"
            wrapper_class="mb-0"
            options={page_size_options(@page_sizes)}
            class="h-7 rounded-md border border-line bg-surface py-0 pl-2 pr-7 text-xs tabular-nums text-ink focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
          />
        </.form>
      </div>
      <div class="flex items-center gap-1" role="list" aria-label="Page navigation">
        <button
          id={"#{@id}-previous"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page - 1}
          disabled={@page.page <= 1}
          aria-label="Previous page"
          title="Previous page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <.icon name="hero-chevron-left" class="size-3.5" />
        </button>
        <%= for step <- pagination_steps(@page) do %>
          <span :if={step == :ellipsis} class="px-1 text-xs text-ink-subtle" aria-hidden="true">…</span>
          <button
            :if={is_integer(step)}
            id={"#{@id}-page-#{step}"}
            type="button"
            phx-click="page"
            phx-value-page={step}
            aria-current={if(step == @page.page, do: "page")}
            aria-label={"Page #{step}"}
            class={[
              "grid size-7 place-items-center rounded-md border text-xs tabular-nums transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25",
              step == @page.page && "border-brand-line bg-brand-surface text-brand-ink",
              step != @page.page && "border-line bg-surface text-ink hover:bg-surface-sunken"
            ]}
          >
            {step}
          </button>
        <% end %>
        <button
          id={"#{@id}-next"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page + 1}
          disabled={@page.page >= @page.total_pages or @page.total_pages == 0}
          aria-label="Next page"
          title="Next page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <.icon name="hero-chevron-right" class="size-3.5" />
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

  defp sort_icon(sort, sort, "asc"), do: "hero-chevron-up"
  defp sort_icon(sort, sort, "desc"), do: "hero-chevron-down"
  defp sort_icon(_sort, _sort_by, _sort_dir), do: "hero-chevron-up-down"

  defp sort_aria(sort, sort, "asc"), do: "ascending"
  defp sort_aria(sort, sort, "desc"), do: "descending"
  defp sort_aria(_sort, _sort_by, _sort_dir), do: "none"

  defp page_summary(%{total_entries: 0}), do: "No results"

  defp page_summary(%{page: page, page_size: page_size, total_entries: total_entries}) do
    first = (page - 1) * page_size + 1
    last = min(page * page_size, total_entries)
    "Showing #{first} to #{last} of #{total_entries} results"
  end

  defp page_size_options(page_sizes), do: Enum.map(page_sizes, &{"#{&1}", &1})

  defp pagination_steps(%{total_pages: 0}), do: []

  defp pagination_steps(%{total_pages: total_pages}) when total_pages <= 5 do
    Enum.to_list(1..total_pages)
  end

  defp pagination_steps(%{page: page, total_pages: total_pages}) do
    [1, 2, page - 1, page, page + 1, total_pages]
    |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
    |> Enum.uniq()
    |> Enum.sort()
    |> insert_page_gaps()
  end

  defp insert_page_gaps(pages) do
    Enum.reduce(pages, [], fn
      page, [] ->
        [page]

      page, steps ->
        if page > List.last(steps) + 1, do: steps ++ [:ellipsis, page], else: steps ++ [page]
    end)
  end
end
