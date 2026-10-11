defmodule Bilimbi.Core.Geonames.Web.Admin1Live do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.Geonames
  alias Bilimbi.Core.Geonames.Web.CamelList

  @page_sizes [25, 50, 100, 300]
  @builtins [
    %{
      id: "country_name",
      label: "Country",
      sort: "country_name",
      sort_id: "admin1-sort-country"
    },
    %{id: "code", label: "Code", sort: "code", sort_id: "admin1-sort-code"},
    %{id: "name", label: "Name", sort: "name", sort_id: "admin1-sort-name"},
    %{id: "alt_name", label: "Alt Name", sort: "alt_name", sort_id: "admin1-sort-alt-name"},
    %{id: "updated_at", label: "Updated", sort: "updated_at", sort_id: "admin1-sort-updated"}
  ]

  @write_guard_opt_out ~w(grid)
  @list ListState.spec!(
          sortable: %{
            country_name: :asc,
            code: :asc,
            name: :asc,
            alt_name: :asc,
            updated_at: :desc
          },
          default_sort: :country_name,
          page_sizes: @page_sizes,
          default_page_size: 25,
          page_size_param: "perPage",
          invalid_page_size: :default,
          filters: [countryIso: {:string, ""}]
        )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:columns, ListColumns.mount("admin1-table", @builtins))
     |> assign(:can_update?, allowed?(socket.assigns.current_scope, "admin.geonames.update"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, parse_index(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state = CamelList.apply_filters(socket.assigns.index_state, filters)
    {:noreply, push_patch(socket, to: admin1_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    state = ListState.next_sort(socket.assigns.index_state, sort_by)
    {:noreply, push_patch(socket, to: admin1_path(state))}
  end

  def handle_event("grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      {:sort, sort_by} -> handle_event("sort", %{"sort" => sort_by}, socket)
      :noop -> {:noreply, socket}
    end
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      socket.assigns.index_state
      |> ListState.put_page(page)
      |> ListState.clamp_to_last_page(socket.assigns.admin1_page, empty: :reset)

    {:noreply, push_patch(socket, to: admin1_path(state))}
  end

  def handle_event("save-admin1-name", _params, %{assigns: %{can_update?: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "You do not have permission to update Admin1 divisions.")}
  end

  def handle_event("save-admin1-name", %{"id" => id, "name" => name}, socket) do
    # `can_update?` only shows the control. The API checks the sealed scope.
    if Authz.can(socket.assigns.current_scope.scope, "admin.geonames.update").allowed do
      save_admin1_name(socket, id, name)
    else
      {:noreply,
       put_flash(socket, :error, "You do not have permission to update Admin1 divisions.")}
    end
  end

  defp save_admin1_name(socket, id, name) do
    case Geonames.update_admin1_name(socket.assigns.current_scope.scope, id, name) do
      {:ok, updated_admin1} ->
        page = socket.assigns.admin1_page

        entries =
          Enum.map(page.entries, &if(&1.id == updated_admin1.id, do: updated_admin1, else: &1))

        {:noreply,
         socket
         |> assign(:admin1_page, %{page | entries: entries})
         |> assign(:columns, ListColumns.load(socket.assigns.columns, entries, & &1.id))
         |> put_flash(:success, "Admin1 division #{updated_admin1.code} updated.")}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, "You do not have permission to update Admin1 divisions.")}

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
            <.icon_button
              icon="bilimbi-pin"
              label="Pin Admin1 Divisions to sidebar"
              context={:inline}
              id="admin1-pin"
              data-nav-pin="nav-admin-geonames-admin1-division"
              aria-pressed="false"
            />
          </:title_actions>
          <:subtitle>States, provinces, and top-level administrative divisions</:subtitle>
        </.header>

        <.filter_toolbar id="admin1-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="admin1-search"
            label="Search Admin1 divisions"
            placeholder="Search by name, code, or country..."
          />
          <:control
            type={:select}
            field={@filters_form[:countryIso]}
            id="admin1-country-filter"
            label="Country"
            options={[{"All Countries", ""} | Geonames.country_options(@filter_countries)]}
          />
        </.filter_toolbar>

        <.card id="admin1-card" inner_class="p-0">
          <.flex_table
            id="admin1-table"
            columns={@columns.column_views}
            rows={@columns.rows}
            mode={@columns.mode}
            zoom={@columns.zoom}
            suggestions={@columns.suggestions}
            add_query={@columns.add_query}
            row_id={&"admin1-#{&1}"}
            event="grid"
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
            caption="Admin1 divisions"
          >
            <:col :let={%{record: admin1}} id="country_name">
              <div class="whitespace-nowrap text-ink-muted">
                <span class="font-mono text-xs">{admin1.country_iso}</span>
                <span class="ml-1">{admin1.country_name || admin1.country_iso}</span>
              </div>
            </:col>
            <:col :let={%{record: admin1}} id="code">
              <span class="whitespace-nowrap font-mono text-ink">{admin1.code}</span>
            </:col>
            <:col :let={%{record: admin1}} id="name">
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
            <:col :let={%{record: admin1}} id="alt_name">
              <span class="whitespace-nowrap text-ink-muted">{admin1.alt_name || "—"}</span>
            </:col>
            <:col :let={%{record: admin1}} id="updated_at">
              <span class="whitespace-nowrap text-xs tabular-nums text-ink-muted">
                <.datetime
                  id={"admin1-#{admin1.id}-updated"}
                  value={admin1.updated_at}
                  format={:date}
                />
              </span>
            </:col>
            <:empty :if={@admin1_page.entries == []}>
              No Admin1 divisions found.
            </:empty>
          </.flex_table>

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
        country_iso: state.filters.countryIso,
        page: state.page,
        page_size: state.page_size,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      })

    socket
    |> assign(:page_title, "Admin1 Divisions")
    |> assign(:page_sizes, @page_sizes)
    |> assign(:admin1_page, admin1_page)
    |> assign(:filter_countries, Geonames.admin1_filter_countries())
    |> assign(:filters_form, ListState.filters_form(state))
    |> assign(:index_state, state)
    |> assign(:columns, ListColumns.load(socket.assigns.columns, admin1_page.entries, & &1.id))
  end

  # The form field stays `countryIso`. The URL key stays `filterCountryIso`.
  defp parse_index(params) do
    params
    |> Map.put("countryIso", Map.get(params, "filterCountryIso", ""))
    |> CamelList.parse(@list)
  end

  defp admin1_path(state) do
    query =
      state
      |> CamelList.to_params()
      |> Map.delete("countryIso")
      |> Map.put("filterCountryIso", state.filters.countryIso)

    ~p"/geonames/admin1?#{query}"
  end
end
