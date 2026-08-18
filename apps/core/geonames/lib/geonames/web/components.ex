defmodule Bilimbi.Core.Geonames.Web.Components do
  @moduledoc false

  use Bilimbi.Base.UI, :html

  attr(:id, :string, required: true)
  attr(:page, :any, required: true)
  attr(:page_sizes, :list, required: true)
  attr(:filters_form, :any, required: true)

  @doc """
  Pager chrome for the GeoNames indexes.

  With zero rows the summary and the page buttons are omitted while the
  rows-per-page selector stays. That split is Belimbing's
  (`resources/core/views/components/ui/pagination.blade.php`): the nav renders
  when `$hasPages || $hasSelector`, the summary is gated on `$summary &&
  $hasPages`, and the page links are gated on `$hasPages` alone. Each table
  already reports emptiness through its own `<:empty>` slot, so a "No results"
  line flanked by two permanently disabled arrows is chrome describing nothing.

  Only the zero case is handled here. Belimbing's `hasPages()` is also false for
  a *single* page, and whether Bilimbi follows it there is the open question on
  issue #306 -- not something to settle by widening this guard to `> 1`.
  """
  def pagination(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Pagination"
      class="flex flex-col gap-2 border-t border-line-subtle px-2 py-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <p :if={@page.total_pages > 0} id={"#{@id}-summary"} class="text-xs text-ink-muted">
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
            class="h-7 w-auto rounded-md border border-line bg-surface py-0 pl-2 pr-6 text-xs tabular-nums text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30"
          />
        </.form>
      </div>
      <div
        :if={@page.total_pages > 0}
        class="flex items-center gap-1"
        role="list"
        aria-label="Page navigation"
      >
        <button
          id={"#{@id}-previous"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page - 1}
          disabled={@page.page <= 1}
          aria-label="Previous page"
          title="Previous page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50"
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
              "grid size-7 place-items-center rounded-md border text-xs tabular-nums transition focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
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
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50"
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
