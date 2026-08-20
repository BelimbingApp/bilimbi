defmodule Bilimbi.Core.Geonames.Web.Admin1Live do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Geonames

  @page_sizes [25, 50, 100, 300]
  @sorts ~w(country_name code name alt_name updated_at)
  @initial_directions %{"updated_at" => "desc"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_update?, allowed?(socket.assigns.current_scope, "admin.geonames.update"))
     |> stream_configure(:admin1, dom_id: &"admin1-#{&1.id}")}
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
      |> Map.put(
        :country_iso,
        Map.get(filters, "countryIso", socket.assigns.index_state.country_iso)
      )
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

  def handle_event("save-admin1-name", _params, %{assigns: %{can_update?: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "You do not have permission to update Admin1 divisions.")}
  end

  def handle_event("save-admin1-name", %{"id" => id, "name" => name}, socket) do
    case Geonames.update_admin1_name(id, name) do
      {:ok, updated_admin1} ->
        {:noreply,
         socket
         |> stream_insert(:admin1, updated_admin1)
         |> put_flash(:info, "Admin1 division #{updated_admin1.code} updated.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save division name.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_nav="admin.geonames.admin1-division"
    >
      <.page id="admin1-index">
        <.header>
          Admin1 Divisions
          <:title_actions>
            <button
              type="button"
              id="admin1-pin"
              data-nav-pin="nav-admin-geonames-admin1-division"
              title="Pin Admin1 Divisions to sidebar"
              aria-label="Pin Admin1 Divisions to sidebar"
              aria-pressed="false"
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:subtitle>States, provinces, and top-level administrative divisions</:subtitle>
        </.header>

        <.card id="admin1-card" inner_class="p-0">
          <.form
            for={@filters_form}
            id="admin1-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_16rem]">
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
                />
                <.input
                  field={@filters_form[:search]}
                  id="admin1-search"
                  type="search"
                  phx-debounce="300"
                  label="Search Admin1 divisions"
                  label_class="sr-only"
                  wrapper_class="mb-0"
                  placeholder="Search by name, code, or country..."
                  class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
                />
              </div>
              <.input
                field={@filters_form[:countryIso]}
                id="admin1-country-filter"
                type="select"
                label="Country"
                label_class="sr-only"
                wrapper_class="mb-0"
                prompt="All Countries"
                options={country_options(@filter_countries)}
                class="h-[2.125rem] w-full rounded-lg border border-line bg-surface px-2 text-sm text-ink shadow-xs transition focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
              />
            </div>
          </.form>

          <.table
            id="admin1-table"
            rows={@streams.admin1}
            row_id={fn {id, _admin1} -> id end}
            row_item={fn {_id, admin1} -> admin1 end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
            caption="Admin1 divisions"
          >
            <:col :let={admin1} label="Country" sort="country_name" sort_id="admin1-sort-country">
              <div class="whitespace-nowrap text-ink-muted">
                <span class="font-mono text-xs">{admin1.country_iso}</span>
                <span class="ml-1">{admin1.country_name || admin1.country_iso}</span>
              </div>
            </:col>
            <:col :let={admin1} label="Code" sort="code" sort_id="admin1-sort-code">
              <span class="whitespace-nowrap font-mono text-ink">{admin1.code}</span>
            </:col>
            <:col :let={admin1} label="Name" sort="name" sort_id="admin1-sort-name">
              <.inline_edit
                :if={@can_update?}
                id={"admin1-#{admin1.id}-name"}
                value={admin1.name}
                id_value={admin1.id}
                save_event="save-admin1-name"
                name="name"
                label="Admin1 division name"
              />
              <span :if={not @can_update?} class="text-ink">{admin1.name}</span>
            </:col>
            <:col :let={admin1} label="Alt Name" sort="alt_name" sort_id="admin1-sort-alt-name">
              <span class="whitespace-nowrap text-ink-muted">{admin1.alt_name || "—"}</span>
            </:col>
            <:col :let={admin1} label="Updated" sort="updated_at" sort_id="admin1-sort-updated">
              <span class="whitespace-nowrap text-xs tabular-nums text-ink-muted">
                <.datetime id={"admin1-#{admin1.id}-updated"} value={admin1.updated_at} format={:date} />
              </span>
            </:col>
            <:empty :if={@admin1_page.entries == []}>
              No Admin1 divisions found.
            </:empty>
          </.table>

          <.pagination
            id="admin1-pagination"
            page={@admin1_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>
      </.page>
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
    |> assign(:page_sizes, @page_sizes)
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
