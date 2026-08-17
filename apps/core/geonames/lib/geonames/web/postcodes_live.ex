defmodule Bilimbi.Core.Geonames.Web.PostcodesLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Geonames

  import Bilimbi.Core.Geonames.Web.Components

  @page_sizes [25, 50, 100, 300]
  @sorts ~w(country_name postcode place_name admin1_code updated_at)
  @summary_sorts ~w(country_name country_iso record_count)
  @initial_directions %{"updated_at" => "desc"}
  @summary_initial_directions %{"record_count" => "desc"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :postcodes, dom_id: &"postcode-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", socket.assigns.index_state.search))
      |> Map.put(:per_page, Map.get(filters, "perPage", socket.assigns.index_state.per_page))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: postcodes_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: postcodes_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  def handle_event("sort-summary", %{"sort" => sort_by}, socket) do
    state = next_summary_sort(socket.assigns.index_state, sort_by)
    {:noreply, push_patch(socket, to: postcodes_path(state))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(
        socket.assigns.index_state,
        :page,
        bounded_page(page, socket.assigns.postcodes_page)
      )

    {:noreply, push_patch(socket, to: postcodes_path(state))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav="admin.geonames.postcode">
      <div id="postcodes-index" class="mx-auto max-w-7xl space-y-5">
        <.header>Geonames Postcodes</.header>

        <section
          :if={@postcode_country_summaries != []}
          id="postcodes-country-summary"
          class="rounded-xl border border-line bg-surface"
        >
          <div class="border-b border-line px-4 py-3">
            <h2 class="text-sm font-semibold text-ink">Postcodes by country</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="border-b border-line bg-surface-sunken">
                <tr>
                  <th
                    scope="col"
                    class="px-4 py-2.5 text-xs font-semibold uppercase tracking-wider text-ink-subtle"
                  >
                    <button
                      id="postcodes-summary-sort-country"
                      type="button"
                      phx-click="sort-summary"
                      phx-value-sort="country_name"
                      class="inline-flex items-center gap-1 rounded transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25"
                    >
                      Country
                      <.icon
                        name={
                          summary_sort_icon(
                            "country_name",
                            @index_state.summary_sort_by,
                            @index_state.summary_sort_dir
                          )
                        }
                        class={[
                          "size-3.5",
                          @index_state.summary_sort_by == "country_name" && "text-action"
                        ]}
                      />
                    </button>
                  </th>
                  <th
                    scope="col"
                    class="px-4 py-2.5 text-xs font-semibold uppercase tracking-wider text-ink-subtle"
                  >
                    <button
                      id="postcodes-summary-sort-iso"
                      type="button"
                      phx-click="sort-summary"
                      phx-value-sort="country_iso"
                      class="inline-flex items-center gap-1 rounded transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25"
                    >
                      ISO
                      <.icon
                        name={
                          summary_sort_icon(
                            "country_iso",
                            @index_state.summary_sort_by,
                            @index_state.summary_sort_dir
                          )
                        }
                        class={[
                          "size-3.5",
                          @index_state.summary_sort_by == "country_iso" && "text-action"
                        ]}
                      />
                    </button>
                  </th>
                  <th
                    scope="col"
                    class="px-4 py-2.5 text-right text-xs font-semibold uppercase tracking-wider text-ink-subtle"
                  >
                    <button
                      id="postcodes-summary-sort-count"
                      type="button"
                      phx-click="sort-summary"
                      phx-value-sort="record_count"
                      class="ml-auto inline-flex items-center gap-1 rounded transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25"
                    >
                      Records
                      <.icon
                        name={
                          summary_sort_icon(
                            "record_count",
                            @index_state.summary_sort_by,
                            @index_state.summary_sort_dir
                          )
                        }
                        class={[
                          "size-3.5",
                          @index_state.summary_sort_by == "record_count" && "text-action"
                        ]}
                      />
                    </button>
                  </th>
                </tr>
              </thead>
              <tbody id="postcodes-country-summary-rows" class="divide-y divide-line-subtle">
                <tr
                  :for={summary <- @postcode_country_summaries}
                  id={"postcode-country-#{summary.country_iso}"}
                  class="hover:bg-surface-sunken"
                >
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink">{summary.country_name}</td>
                  <td class="whitespace-nowrap px-4 py-2.5 font-mono text-xs text-ink-muted">
                    {summary.country_iso}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-right tabular-nums text-ink">
                    {format_integer(summary.record_count)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="rounded-xl border border-line bg-surface">
          <.form
            for={@filters_form}
            id="postcodes-filters"
            phx-change="filters"
            class="px-2 pt-2"
          >
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
              />
              <.input
                field={@filters_form[:search]}
                id="postcodes-search"
                type="search"
                phx-debounce="300"
                label="Search postcodes"
                label_class="sr-only"
                wrapper_class="mb-0"
                placeholder="Search by postcode, place name, or country..."
                class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
              />
            </div>
          </.form>

          <div class="overflow-x-auto px-2 pt-2">
            <table class="w-full text-left text-sm">
              <caption class="sr-only">Geonames postcodes</caption>
              <thead class="border-y border-line bg-surface-sunken">
                <tr>
                  <.sortable_heading
                    id="postcodes-sort-country"
                    label="Country"
                    sort="country_name"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="postcodes-sort-postcode"
                    label="Postcode"
                    sort="postcode"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="postcodes-sort-place"
                    label="Place Name"
                    sort="place_name"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="postcodes-sort-admin1"
                    label="Admin1 Code"
                    sort="admin1_code"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="postcodes-sort-updated"
                    label="Updated"
                    sort="updated_at"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                </tr>
              </thead>
              <tbody id="postcodes-table" phx-update="stream" class="divide-y divide-line-subtle">
                <tr
                  :for={{id, postcode} <- @streams.postcodes}
                  id={id}
                  class="hover:bg-surface-sunken"
                >
                  <td class="whitespace-nowrap px-2 py-1.5 text-ink-muted">
                    <span class="font-mono text-xs">{postcode.country_iso}</span>
                    <span class="ml-1">{postcode.country_name || postcode.country_iso}</span>
                  </td>
                  <td class="whitespace-nowrap px-2 py-1.5 font-medium tabular-nums text-ink">
                    {postcode.postcode}
                  </td>
                  <td class="whitespace-nowrap px-2 py-1.5 text-ink-muted">
                    {postcode.place_name}
                  </td>
                  <td class="whitespace-nowrap px-2 py-1.5 tabular-nums text-ink-muted">
                    {postcode.admin1_code || "—"}
                  </td>
                  <td class="whitespace-nowrap px-2 py-1.5 text-xs tabular-nums text-ink-muted">
                    <.datetime id={"#{id}-updated"} value={postcode.updated_at} format={:date} />
                  </td>
                </tr>
                <tr :if={@postcodes_page.entries == []} id="postcodes-empty">
                  <td colspan="5" class="px-2 py-8 text-center text-ink-muted">
                    No postcodes found.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.pagination
            id="postcodes-pagination"
            page={@postcodes_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp load_page(socket, state) do
    postcodes_page =
      Geonames.page_postcodes(%{
        search: state.search,
        page: state.page,
        page_size: state.per_page,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      })

    postcode_country_summaries =
      Geonames.list_postcode_country_summaries(%{
        sort_by: state.summary_sort_by,
        sort_dir: state.summary_sort_dir
      })

    state = %{state | page: postcodes_page.page, per_page: postcodes_page.page_size}

    socket
    |> assign(:page_title, "Geonames Postcodes")
    |> assign(:page_sizes, @page_sizes)
    |> assign(:postcodes_page, postcodes_page)
    |> assign(:postcode_country_summaries, postcode_country_summaries)
    |> assign(
      :filters_form,
      to_form(%{"search" => state.search, "perPage" => state.per_page}, as: :filters)
    )
    |> assign(:index_state, state)
    |> stream(:postcodes, postcodes_page.entries, reset: true)
  end

  defp state_from_params(params) do
    sort_by = normalize_sort(Map.get(params, "sortBy"))
    summary_sort_by = normalize_summary_sort(Map.get(params, "summarySortBy"))

    %{
      search: Map.get(params, "search", ""),
      page: parse_page(Map.get(params, "page")),
      per_page: normalize_page_size(Map.get(params, "perPage")),
      sort_by: sort_by,
      sort_dir: normalize_direction(Map.get(params, "sortDir"), sort_by),
      summary_sort_by: summary_sort_by,
      summary_sort_dir:
        normalize_summary_direction(Map.get(params, "summarySortDir"), summary_sort_by)
    }
  end

  defp next_sort(state, sort_by) do
    sort_by = normalize_sort(sort_by)

    %{
      state
      | page: 1,
        sort_by: sort_by,
        sort_dir:
          if(state.sort_by == sort_by,
            do: flip_direction(state.sort_dir),
            else: default_direction(sort_by)
          )
    }
  end

  defp next_summary_sort(state, sort_by) do
    sort_by = normalize_summary_sort(sort_by)

    %{
      state
      | summary_sort_by: sort_by,
        summary_sort_dir:
          if(
            state.summary_sort_by == sort_by,
            do: flip_direction(state.summary_sort_dir),
            else: default_summary_direction(sort_by)
          )
    }
  end

  defp postcodes_path(state) do
    ~p"/geonames/postcodes?#{%{search: state.search, page: state.page, perPage: state.per_page, sortBy: state.sort_by, sortDir: state.sort_dir, summarySortBy: state.summary_sort_by, summarySortDir: state.summary_sort_dir}}"
  end

  defp normalize_sort(sort_by) when sort_by in @sorts, do: sort_by
  defp normalize_sort(_sort_by), do: "country_name"

  defp normalize_summary_sort(sort_by) when sort_by in @summary_sorts, do: sort_by
  defp normalize_summary_sort(_sort_by), do: "country_name"

  defp normalize_direction(direction, _sort_by) when direction in ["asc", "desc"], do: direction
  defp normalize_direction(_direction, sort_by), do: default_direction(sort_by)

  defp normalize_summary_direction(direction, _sort_by) when direction in ["asc", "desc"],
    do: direction

  defp normalize_summary_direction(_direction, sort_by), do: default_summary_direction(sort_by)

  defp default_direction(sort_by), do: Map.get(@initial_directions, sort_by, "asc")

  defp default_summary_direction(sort_by),
    do: Map.get(@summary_initial_directions, sort_by, "asc")

  defp flip_direction("asc"), do: "desc"
  defp flip_direction(_direction), do: "asc"

  defp normalize_page_size(value) do
    value = parse_page(value)
    Enum.find(@page_sizes, List.last(@page_sizes), &(&1 >= value))
  end

  defp parse_page(value) when is_integer(value) and value > 0, do: value

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp bounded_page(value, page) do
    page_number = parse_page(value)
    max(page.total_pages, 1) |> min(page_number) |> max(1)
  end

  defp summary_sort_icon(sort, sort, "asc"), do: "hero-chevron-up"
  defp summary_sort_icon(sort, sort, "desc"), do: "hero-chevron-down"
  defp summary_sort_icon(_sort, _sort_by, _sort_dir), do: "hero-chevron-up-down"
end
