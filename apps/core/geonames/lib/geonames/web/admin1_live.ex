defmodule Bilimbi.Core.Geonames.Web.Admin1Live do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Geonames

  import Bilimbi.Core.Geonames.Web.Components

  @page_sizes [20, 50, 100, 300]
  @sorts ~w(country_name code name alt_name updated_at)
  @initial_directions %{"updated_at" => "desc"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :admin1, dom_id: &"admin1-#{&1.id}")}
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
      |> Map.put(:country_iso, Map.get(filters, "countryIso", ""))
      |> Map.put(:per_page, Map.get(filters, "perPage", socket.assigns.index_state.per_page))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: admin1_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: admin1_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(socket.assigns.index_state, :page, bounded_page(page, socket.assigns.admin1_page))

    {:noreply, push_patch(socket, to: admin1_path(state))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav="admin.geonames.admin1-division">
      <div id="admin1-index" class="mx-auto max-w-7xl">
        <.header>
          Admin1 Divisions
          <:subtitle>States, provinces, and top-level administrative divisions</:subtitle>
        </.header>

        <div class="rounded-xl border border-line bg-surface">
          <.form
            for={@filters_form}
            id="admin1-filters"
            phx-change="filters"
            class="px-4 pt-4"
          >
            <div class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_16rem_12rem]">
              <.input
                field={@filters_form[:search]}
                id="admin1-search"
                type="search"
                phx-debounce="300"
                label="Search Admin1 divisions"
                placeholder="Search by name, code, or country..."
              />
              <.input
                field={@filters_form[:countryIso]}
                id="admin1-country-filter"
                type="select"
                label="Country"
                prompt="All Countries"
                options={country_options(@filter_countries)}
              />
              <.input
                field={@filters_form[:perPage]}
                id="admin1-page-size"
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
                    id="admin1-sort-country"
                    label="Country"
                    sort="country_name"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="admin1-sort-code"
                    label="Code"
                    sort="code"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="admin1-sort-name"
                    label="Name"
                    sort="name"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="admin1-sort-alt-name"
                    label="Alt Name"
                    sort="alt_name"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                  <.sortable_heading
                    id="admin1-sort-updated"
                    label="Updated"
                    sort="updated_at"
                    sort_by={@index_state.sort_by}
                    sort_dir={@index_state.sort_dir}
                  />
                </tr>
              </thead>
              <tbody id="admin1-table" phx-update="stream" class="divide-y divide-line-subtle">
                <tr
                  :for={{id, admin1} <- @streams.admin1}
                  id={id}
                  class="hover:bg-surface-sunken"
                >
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink-muted">
                    <span class="font-mono text-xs">{admin1.country_iso}</span>
                    <span class="ml-1">{admin1.country_name || admin1.country_iso}</span>
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 font-mono text-ink">{admin1.code}</td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink">{admin1.name}</td>
                  <td class="whitespace-nowrap px-4 py-2.5 text-ink-muted">
                    {admin1.alt_name || "—"}
                  </td>
                  <td class="whitespace-nowrap px-4 py-2.5 tabular-nums text-ink-muted">
                    {format_date(admin1.updated_at)}
                  </td>
                </tr>
                <tr :if={@admin1_page.entries == []} id="admin1-empty">
                  <td colspan="5" class="px-4 py-8 text-center text-ink-muted">
                    No Admin1 divisions found.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.pagination id="admin1-pagination" page={@admin1_page} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_page(socket, state) do
    admin1_page =
      Geonames.page_admin1(%{
        search: state.search,
        country_iso: state.country_iso,
        page: state.page,
        page_size: state.per_page,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      })

    state = %{state | page: admin1_page.page, per_page: admin1_page.page_size}

    socket
    |> assign(:page_title, "Admin1 Divisions")
    |> assign(:admin1_page, admin1_page)
    |> assign(:filter_countries, Geonames.admin1_filter_countries())
    |> assign(
      :filters_form,
      to_form(
        %{
          "search" => state.search,
          "countryIso" => state.country_iso,
          "perPage" => state.per_page
        },
        as: :filters
      )
    )
    |> assign(:index_state, state)
    |> stream(:admin1, admin1_page.entries, reset: true)
  end

  defp state_from_params(params) do
    sort_by = normalize_sort(Map.get(params, "sortBy"))

    %{
      search: Map.get(params, "search", ""),
      country_iso: Map.get(params, "filterCountryIso", ""),
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

  defp admin1_path(state) do
    ~p"/geonames/admin1?#{%{search: state.search, filterCountryIso: state.country_iso, page: state.page, perPage: state.per_page, sortBy: state.sort_by, sortDir: state.sort_dir}}"
  end

  defp country_options(countries), do: Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})
  defp page_size_options, do: Enum.map(@page_sizes, &{"#{&1} rows", &1})

  defp normalize_sort(sort_by) when sort_by in @sorts, do: sort_by
  defp normalize_sort(_sort_by), do: "country_name"

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
