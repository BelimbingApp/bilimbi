defmodule Bilimbi.Core.Geonames.Web.CountriesLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Geonames

  import Bilimbi.Core.Geonames.Web.Components

  @page_sizes [25, 50, 100, 300]
  @sorts ~w(iso country capital phone currency_code population updated_at)
  @initial_directions %{"population" => "desc", "updated_at" => "desc"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_update?, allowed?(socket.assigns.current_scope, "admin.geonames.update"))
     |> assign(:updating_countries?, false)
     |> stream_configure(:countries, dom_id: &"country-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("save-country-name", _params, %{assigns: %{can_update?: false}} = socket) do
    {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}
  end

  def handle_event("save-country-name", %{"id" => id, "country" => name}, socket) do
    # `id` arrives from the client. `String.to_integer/1` raised on anything
    # non-numeric and took the LiveView down with it; `update_country_name/2`
    # already parses binaries safely and answers `:not_found` for garbage
    # (`geonames.ex:141-150`), so passing it straight through is both shorter
    # and harder to break (#302).
    case Geonames.update_country_name(id, name) do
      {:ok, updated_country} ->
        {:noreply,
         socket
         |> stream_insert(:countries, updated_country)
         |> put_flash(:info, "Country #{updated_country.iso} name updated.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save country name.")}
    end
  end

  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", socket.assigns.index_state.search))
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

  def handle_event("update-countries", _params, %{assigns: %{can_update?: false}} = socket) do
    {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}
  end

  def handle_event("update-countries", _params, %{assigns: %{updating_countries?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("update-countries", _params, socket) do
    {:noreply,
     socket
     |> assign(:updating_countries?, true)
     |> start_async(:update_countries, fn ->
       Geonames.import_reference_data(datasets: [:countries])
     end)}
  end

  @impl true
  def handle_async(:update_countries, {:ok, {:ok, result}}, socket) do
    socket =
      socket
      |> assign(:updating_countries?, false)
      |> put_flash(:info, update_success_message(result))

    {:noreply, load_page(socket, socket.assigns.index_state)}
  end

  def handle_async(:update_countries, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:updating_countries?, false)
     |> put_flash(:error, update_error_message(reason))}
  end

  def handle_async(:update_countries, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:updating_countries?, false)
     |> put_flash(:error, update_error_message(:task_exit))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav="admin.geonames.country">
      <.page id="countries-index">
        <.header>
          Countries
          <:title_actions>
            <button
              type="button"
              id="countries-pin"
              data-nav-pin="nav-admin-geonames-country"
              title="Pin Countries to sidebar"
              aria-label="Pin Countries to sidebar"
              aria-pressed="false"
              class="grid size-6 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:actions>
            <.button
              :if={@can_update?}
              id="countries-update"
              type="button"
              variant="primary"
              phx-click="update-countries"
              disabled={@updating_countries?}
              class="px-3 py-1.5"
            >
              <.icon
                name="hero-arrow-path"
                class={["size-4", @updating_countries? && "animate-spin"]}
              />
              <span>{if @updating_countries?, do: "Updating…", else: "Update"}</span>
            </.button>
          </:actions>
        </.header>

        <.card id="countries-card" inner_class="p-0">
          <.form
            for={@filters_form}
            id="countries-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
              />
              <.input
                field={@filters_form[:search]}
                id="countries-search"
                type="search"
                phx-debounce="300"
                label="Search countries"
                label_class="sr-only"
                wrapper_class="mb-0"
                placeholder="Search by country name or ISO code..."
                class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
              />
            </div>
          </.form>

          <.table
            id="countries-table"
            rows={@streams.countries}
            row_id={fn {id, _country} -> id end}
            row_item={fn {_id, country} -> country end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
            caption="Countries"
          >
            <:col :let={country} label="ISO" sort="iso" sort_id="countries-sort-iso">
              <span class="whitespace-nowrap font-medium tabular-nums text-ink">{country.iso}</span>
            </:col>
            <:col :let={country} label="Country" sort="country" sort_id="countries-sort-country">
              <.inline_edit
                :if={@can_update?}
                id={"country-#{country.id}-name"}
                value={country.country}
                id_value={country.id}
                save_event="save-country-name"
                name="country"
                label="Country name"
              />
              <span :if={not @can_update?} class="font-medium text-ink">{country.country}</span>
            </:col>
            <:col :let={country} label="Capital" sort="capital" sort_id="countries-sort-capital">
              <span class="whitespace-nowrap tabular-nums text-ink-muted">{country.capital || "—"}</span>
            </:col>
            <:col :let={country} label="Phone" sort="phone" sort_id="countries-sort-phone">
              <span class="whitespace-nowrap tabular-nums text-ink-muted">{country.phone || "—"}</span>
            </:col>
            <:col :let={country} label="Currency" sort="currency_code" sort_id="countries-sort-currency">
              <span class="whitespace-nowrap text-ink-muted">{country.currency_code || "—"}</span>
            </:col>
            <:col :let={country} label="Population" sort="population" sort_id="countries-sort-population" align={:right}>
              <span class="whitespace-nowrap tabular-nums text-ink-muted">{format_integer(country.population)}</span>
            </:col>
            <:col :let={country} label="Updated" sort="updated_at" sort_id="countries-sort-updated">
              <span class="whitespace-nowrap text-xs tabular-nums text-ink-muted">
                <.datetime
                  id={"country-#{country.id}-updated"}
                  value={country.updated_at}
                  format={:date}
                />
              </span>
            </:col>
            <:empty :if={@countries_page.entries == []}>
              No countries found.
            </:empty>
          </.table>

          <.pagination
            id="countries-pagination"
            page={@countries_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>
      </.page>
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
    |> assign(:page_sizes, @page_sizes)
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

  # A fallback is NOT an update. `:fallback` means the download failed and the
  # existing local file was reused -- previously indistinguishable from a 304,
  # because both carry `cached: true` and only `:status` told them apart (#273).
  # Saying "updated" there tells an operator with a week-dead proxy that their
  # country data is current.
  defp update_success_message(%{
         countries:
           %{download_status: {:fallback, cause}, imported: imported, skipped: skipped} = result
       }) do
    "Countries were not updated: #{fallback_cause(cause)}#{as_of(result[:cached_at])}. " <>
      "Kept the existing local data (#{imported} imported, #{skipped} skipped). Try Update again later."
  end

  defp update_success_message(%{
         countries: %{cached: cached, imported: imported, skipped: skipped}
       }) do
    source =
      if cached, do: "the current local GeoNames download", else: "a fresh GeoNames download"

    "Countries updated from #{source}: #{imported} imported, #{skipped} skipped."
  end

  defp update_success_message(_result), do: "Countries updated from GeoNames."

  # A 503 is not the same as an unplugged cable, and telling an operator to
  # check their firewall when GeoNames is simply down wastes their afternoon.
  defp fallback_cause(:unreachable), do: "GeoNames could not be reached"
  defp fallback_cause({:http_status, status}), do: "GeoNames returned an error (HTTP #{status})"

  defp as_of(%DateTime{} = cached_at),
    do: ", so this data is from #{Calendar.strftime(cached_at, "%d %b %Y")}"

  defp as_of(_cached_at), do: ""

  defp update_error_message({:download, :countries, {:request, error}}) do
    if network_timeout_or_unreachable?(error) do
      "Countries were not changed. Bilimbi could not connect to download.geonames.org. Check internet, proxy, or firewall access, then try Update again. If it persists, contact your administrator."
    else
      "Countries were not changed because the GeoNames download failed. Try Update again; if it persists, contact your administrator."
    end
  end

  defp update_error_message({:download, :countries, {:http_status, status}}) do
    "Countries were not changed. GeoNames responded with HTTP #{status}. Try Update again later; if it persists, contact your administrator."
  end

  defp update_error_message({:import, :countries, _reason}) do
    "Countries were not changed. GeoNames data was downloaded but could not be imported, and the existing data was kept. Try Update again; if it persists, contact your administrator."
  end

  defp update_error_message(_reason) do
    "Countries were not changed because the GeoNames update did not finish. Try Update again; if it persists, contact your administrator."
  end

  defp network_timeout_or_unreachable?(%{reason: reason})
       when reason in [:timeout, :connect_timeout, :nxdomain, :econnrefused, :closed, :etimedout] do
    true
  end

  defp network_timeout_or_unreachable?(%{reason: {:timeout, _}}), do: true
  defp network_timeout_or_unreachable?(_), do: false
end
