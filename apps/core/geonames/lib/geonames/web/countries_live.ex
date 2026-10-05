defmodule Bilimbi.Core.Geonames.Web.CountriesLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.Geonames
  alias Bilimbi.Core.Geonames.Web.CamelList

  import Bilimbi.Core.Geonames.Web.Components

  @page_sizes [25, 50, 100, 300]
  @list ListState.spec!(
          sortable: %{
            iso: :asc,
            country: :asc,
            capital: :asc,
            phone: :asc,
            currency_code: :asc,
            population: :desc,
            updated_at: :desc
          },
          default_sort: :country,
          page_sizes: @page_sizes,
          default_page_size: 25,
          page_size_param: "perPage",
          invalid_page_size: :default
        )

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
    {:noreply, load_page(socket, CamelList.parse(params, @list))}
  end

  @impl true
  def handle_event("save-country-name", _params, %{assigns: %{can_update?: false}} = socket) do
    {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}
  end

  def handle_event("save-country-name", %{"id" => id, "country" => name}, socket) do
    # `id` arrives from the client. `String.to_integer/1` raised on anything
    # non-numeric and took the LiveView down with it; `update_country_name/3`
    # already parses binaries safely and answers `:not_found` for garbage,
    # so passing it straight through is both shorter and harder to break (#302).
    # `can_update?` only shows the control. This asks again, and the API asks
    # with the sealed scope, so a grant revoked after mount does not rename.
    if country_update_allowed?(socket) do
      save_country_name(socket, id, name)
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}
    end
  end

  def handle_event("filters", %{"filters" => filters}, socket) do
    state = CamelList.apply_filters(socket.assigns.index_state, filters)
    {:noreply, push_patch(socket, to: countries_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    state = ListState.next_sort(socket.assigns.index_state, sort_by)
    {:noreply, push_patch(socket, to: countries_path(state))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      socket.assigns.index_state
      |> ListState.put_page(page)
      |> ListState.clamp_to_last_page(socket.assigns.countries_page, empty: :reset)

    {:noreply, push_patch(socket, to: countries_path(state))}
  end

  def handle_event("update-countries", _params, %{assigns: %{can_update?: false}} = socket) do
    {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}
  end

  def handle_event("update-countries", _params, %{assigns: %{updating_countries?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("update-countries", _params, socket) do
    if country_update_allowed?(socket) do
      scope = socket.assigns.current_scope.scope

      {:noreply,
       socket
       |> assign(:updating_countries?, true)
       |> start_async(:update_countries, fn ->
         Geonames.import_reference_data(scope, datasets: [:countries])
       end)}
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}
    end
  end

  defp save_country_name(socket, id, name) do
    case Geonames.update_country_name(socket.assigns.current_scope.scope, id, name) do
      {:ok, updated_country} ->
        {:noreply,
         socket
         |> stream_insert(:countries, updated_country)
         |> put_flash(:success, "Country #{updated_country.iso} name updated.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to update countries.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save country name.")}
    end
  end

  defp country_update_allowed?(socket) do
    Authz.can(socket.assigns.current_scope.scope, "admin.geonames.update").allowed
  end

  @impl true
  def handle_async(:update_countries, {:ok, {:ok, result}}, socket) do
    {kind, message} = update_message(result)

    socket =
      socket
      |> assign(:updating_countries?, false)
      |> put_flash(kind, message)

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
            <.icon_button
              icon="bilimbi-pin"
              label="Pin Countries to sidebar"
              context={:inline}
              id="countries-pin"
              data-nav-pin="nav-admin-geonames-country"
              aria-pressed="false"
            />
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
                name="refresh"
                class={["size-4", @updating_countries? && "animate-spin"]}
              />
              <span>{if @updating_countries?, do: "Updating…", else: "Update"}</span>
            </.button>
          </:actions>
        </.header>

        <.filter_toolbar id="countries-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="countries-search"
            label="Search countries"
            placeholder="Search by country name or ISO code..."
          />
        </.filter_toolbar>

        <.card id="countries-card" inner_class="p-0">
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
            <:col
              :let={country}
              label="Currency"
              sort="currency_code"
              sort_id="countries-sort-currency"
            >
              <span class="whitespace-nowrap text-ink-muted">{country.currency_code || "—"}</span>
            </:col>
            <:col
              :let={country}
              label="Population"
              sort="population"
              sort_id="countries-sort-population"
              align={:right}
            >
              <span class="whitespace-nowrap tabular-nums text-ink-muted">{format_integer(
                country.population
              )}</span>
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
        page_size: state.page_size,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      })

    socket
    |> assign(:page_title, "Countries")
    |> assign(:page_sizes, @page_sizes)
    |> assign(:countries_page, countries_page)
    |> assign(:filters_form, ListState.filters_form(state))
    |> assign(:index_state, state)
    |> stream(:countries, countries_page.entries, reset: true)
  end

  defp countries_path(state) do
    ~p"/geonames/countries?#{CamelList.to_params(state)}"
  end

  # A fallback is NOT an update. `:fallback` means the download failed and the
  # existing local file was reused -- previously indistinguishable from a 304,
  # because both carry `cached: true` and only `:status` told them apart (#273).
  # Saying "updated" there tells an operator with a week-dead proxy that their
  # country data is current.
  defp update_message(%{
         countries:
           %{download_status: {:fallback, cause}, imported: imported, skipped: skipped} = result
       }) do
    {:warning,
     "Countries were not updated: #{fallback_cause(cause)}#{as_of(result[:cached_at])}. " <>
       "Kept the existing local data (#{imported} imported, #{skipped} skipped). Try Update again later."}
  end

  defp update_message(%{
         countries: %{cached: cached, imported: imported, skipped: skipped}
       }) do
    source =
      if cached, do: "the current local GeoNames download", else: "a fresh GeoNames download"

    {:success, "Countries updated from #{source}: #{imported} imported, #{skipped} skipped."}
  end

  defp update_message(_result), do: {:success, "Countries updated from GeoNames."}

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
