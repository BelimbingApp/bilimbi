defmodule Bilimbi.Core.Geonames.Web.CountriesLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Geonames

  import Bilimbi.Core.Geonames.Web.Components

  @page_sizes [20, 50, 100, 300]
  @sorts ~w(iso country capital phone currency_code population updated_at)
  @initial_directions %{"population" => "desc", "updated_at" => "desc"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :countries, dom_id: &"country-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", ""))
      |> Map.put(:per_page, Map.get(filters, "perPage", socket.assigns.index_state.per_page))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: countries_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: countries_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(
        socket.assigns.index_state,
        :page,
        bounded_page(page, socket.assigns.countries_page)
      )

    {:noreply, push_patch(socket, to: countries_path(state))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:geonames}>
      <div id="countries-index" class="mx-auto max-w-7xl">
        <.header>
          Countries
        </.header>

        <div class="rounded-xl border border-line bg-surface">
          <.form
            for={@filters_form}
            id="countries-filters"
            phx-change="filters"
            class="px-4 pt-4"
          >
            <div class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_12rem]">
              <.input
                field={@filters_form[:search]}
                id="countries-search"
                type="search"
                phx-debounce="300"
                label="Search countries"
                placeholder="Search by country name or ISO code..."
              />
              <.input
                field={@filters_form[:perPage]}
                id="countries-page-size"
                type="select"
                label="Rows per page"
                options={page_size_options()}
              />
            </div>
          </.form>

          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="border-y border-line bg-surface-sunken">
                <tr>
                  <.sortable_heading
                    id="countries-sort-iso"
                    label="ISO"
                    sort="iso"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="countries-sort-country"
                    label="Country"
                    sort="country"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="countries-sort-capital"
                    label="Capital"
                    sort="capital"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="countries-sort-phone"
                    label="Phone"
                    sort="phone"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="countries-sort-currency"
                    label="Currency"
                    sort="currency_code"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="countries-sort-population"
                    label="Population"
                    sort="population"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                    align={:right}
                  />
                  <.sortable_heading
                    id="countries-sort-updated"
                    label="Updated"
                    sort="updated_at"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                </tr>
              </thead>
              <tbody id="countries-table" phx-update="stream" class="divide-y divide-line-subtle">
                <tr
                  :for={{id, country} <- @streams.countries}
                  id={id}
                  class="hover:bg-surface-sunken"
                >
                  <td class="whitespace-nowrap px-4 py-2.5 font-medium tabular-nums text-ink">
                    {country.iso}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink">{country.country}</td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink-muted">
                    {country.capital || "—"}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 tabular-nums text-ink-muted">
                    {country.phone || "—"}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink-muted">
                    {country.currency_code || "—"}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-right tabular-nums text-ink-muted">
                    {format_integer(country.population)}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 tabular-nums text-ink-muted">
                    {format_date(country.updated_at)}
                  </td>
                </tr>
                <tr :if={@countries_page.entries == []} id="countries-empty">
                  <td colspan="7" class="px-4 py-8 text-center text-ink-muted">
                    No countries found.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.pagination id="countries-pagination" page={@countries_page} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_page(socket, state) do
    countries_page =
      Geonames.page_countries(%{
        search: state.search,
        page: state.page,
        page_size: state.per_page,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      })

    state = %{state | page: countries_page.page, per_page: countries_page.page_size}

    socket
    |> assign(:page_title, "Countries")
    |> assign(:countries_page, countries_page)
    |> assign(
      :filters_form,
      to_form(%{"search" => state.search, "perPage" => state.per_page}, as: :filters)
    )
    |> assign(:index_state, state)
    |> stream(:countries, countries_page.entries, reset: true)
  end

  defp state_from_params(params) do
    sort_by = normalize_sort(Map.get(params, "sortBy"))

    %{
      search: Map.get(params, "search", ""),
      page: parse_page(Map.get(params, "page")),
      per_page: normalize_page_size(Map.get(params, "perPage")),
      sort_by: sort_by,
      sort_dir: normalize_direction(Map.get(params, "sortDir"), sort_by)
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

  defp countries_path(state) do
    ~p"/geonames/countries?#{%{search: state.search, page: state.page, perPage: state.per_page, sortBy: state.sort_by, sortDir: state.sort_dir}}"
  end

  defp page_size_options, do: Enum.map(@page_sizes, &{"#{&1} rows", &1})

  defp normalize_sort(sort_by) when sort_by in @sorts, do: sort_by
  defp normalize_sort(_sort_by), do: "country"

  defp normalize_direction(direction, _sort_by) when direction in ["asc", "desc"], do: direction
  defp normalize_direction(_direction, sort_by), do: default_direction(sort_by)

  defp default_direction(sort_by), do: Map.get(@initial_directions, sort_by, "asc")
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
end
