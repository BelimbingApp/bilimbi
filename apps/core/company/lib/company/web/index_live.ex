defmodule Bilimbi.Core.Company.Web.IndexLive do
  @moduledoc """
  Tenant-wide company administration index, via
  `Bilimbi.Core.Company.list_administration_page/2`.

  Search, status filter, sort, page, and page size live in the URL, so a
  filtered view can be shared, reloaded, and stepped through with the
  browser history. Parity source: Belimbing's Company Management index at
  pin e70b4d33; deleting a company has no Bilimbi domain operation yet, so
  the source's row delete is deliberately absent (#622).
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Grid.Web.PageColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.AdministrationPage

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25
  @default_sort "name"
  @default_dir "asc"
  @statuses ["active", "suspended", "pending", "archived"]

  # The query string stays `sort`, `dir`, `status`, and `per_page`, and omits
  # a value that is already the default. `ListState` speaks `sort_by` /
  # `sort_dir`; `companies_path/1` translates. A key rename would break links
  # this page already shares.
  @list ListState.spec!(
          sortable: %{name: :asc, status: :asc, jurisdiction: :asc},
          default_sort: :name,
          page_sizes: @page_sizes,
          default_page_size: @default_page_size,
          page_size_param: "per_page",
          invalid_page_size: :default,
          filters: [status_filter: {:one_of, ["all" | @statuses], "all"}],
          omit_blank: [:search]
        )

  # The columns this page draws itself; walked catalog columns join them
  # through PageColumns.
  @builtins [
    %{id: "name", label: "Name", type: :string, sort: "name", sort_id: "companies-sort-name"},
    %{id: "code", label: "Code", type: :string},
    %{id: "parent_name", label: "Parent", type: :string},
    %{
      id: "status",
      label: "Status",
      type: :enum,
      sort: "status",
      sort_id: "companies-sort-status"
    },
    %{
      id: "jurisdiction",
      label: "Jurisdiction",
      type: :string,
      sort: "jurisdiction",
      sort_id: "companies-sort-jurisdiction"
    }
  ]

  # Column, lens and zoom operations rearrange the reading of the list; the
  # page writes nothing through them.
  @write_guard_opt_out ~w(grid)

  @impl true
  def mount(_params, _session, socket) do
    state = ListState.parse(%{}, @list)

    {:ok,
     socket
     |> assign(:page_title, "Companies")
     |> assign(:active_nav, "admin.company")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:index_state, state)
     |> assign(:companies_page, empty_page())
     |> assign(:filters_form, ListState.filters_form(state))
     |> assign(
       :columns,
       PageColumns.mount(socket.assigns.current_scope.scope, "companies", @builtins)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = ListState.parse(list_params(params), @list)
    columns = PageColumns.from_params(socket.assigns.columns, params)
    {:noreply, socket |> assign(:columns, columns) |> load_page(state)}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    posted =
      filters
      |> normalize_posted("search", &inbound_search/1)
      |> normalize_posted("status_filter", &inbound_status/1)

    state = ListState.apply_filters(socket.assigns.index_state, posted)
    {:noreply, push_patch(socket, to: companies_path(state, socket.assigns.columns))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    state = ListState.next_sort(socket.assigns.index_state, inbound_sort(sort_by))
    {:noreply, push_patch(socket, to: companies_path(state, socket.assigns.columns))}
  end

  def handle_event("grid", params, socket) do
    case PageColumns.handle(socket.assigns.columns, params, "companies") do
      {:patch, columns} ->
        {:noreply, push_patch(socket, to: companies_path(socket.assigns.index_state, columns))}

      {:update, columns} ->
        {:noreply, assign(socket, :columns, columns)}

      {:sort, key} ->
        handle_event("sort", %{"sort" => key}, socket)

      {:window, event, payload} ->
        {:noreply, push_event(socket, event, payload)}

      {:reply, text} ->
        {:reply, %{text: text}, socket}

      :noop ->
        {:noreply, socket}
    end
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  def handle_event("page", %{"page" => page}, socket) do
    state = ListState.put_page(socket.assigns.index_state, page)
    {:noreply, push_patch(socket, to: companies_path(state, socket.assigns.columns))}
  end

  defp load_page(socket, state) do
    scope = socket.assigns.current_scope.scope

    options = [
      page: state.page,
      page_size: state.page_size,
      search: state.search,
      status_filter: query_status(state.filters.status_filter),
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Company.list_administration_page(scope, options) do
      {:ok, %AdministrationPage{} = page} ->
        corrected = ListState.clamp_to_last_page(state, page, empty: :reset)

        if corrected.page != state.page do
          push_patch(socket, to: companies_path(corrected, socket.assigns.columns))
        else
          socket
          |> assign(:index_state, state)
          |> assign(:companies_page, page)
          |> assign(:filters_form, ListState.filters_form(state))
          |> assign(
            :columns,
            PageColumns.load(socket.assigns.columns, page.entries, & &1.id, &builtin_cells/1)
          )
        end

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load companies.")
        |> assign(:index_state, state)
        |> assign(:companies_page, empty_page())
        |> assign(
          :columns,
          PageColumns.load(socket.assigns.columns, [], & &1.id, &builtin_cells/1)
        )
    end
  end

  defp builtin_cells(company) do
    %{
      "name" => company.name,
      "code" => company.code,
      "parent_name" => company.parent_name,
      "status" => company.status,
      "jurisdiction" => company.jurisdiction
    }
  end

  defp listed(page, id), do: Enum.find(page.entries, &(&1.id == id))

  defp empty_page do
    %AdministrationPage{
      entries: [],
      page: 1,
      page_size: @default_page_size,
      total_entries: 0,
      total_pages: 0,
      has_prev?: false,
      has_next?: false
    }
  end

  defp list_params(params) do
    %{
      "search" => inbound_search(params["search"] || params["q"]),
      "page" => params["page"],
      "per_page" => params["per_page"] || params["perPage"],
      "sort_by" => inbound_sort(params["sort"]),
      "sort_dir" => params["dir"],
      "status_filter" => inbound_status(params["status"] || params["status_filter"])
    }
  end

  defp inbound_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> ""
      trimmed -> String.slice(trimmed, 0, 255)
    end
  end

  defp inbound_search(_value), do: ""

  defp inbound_status(value) when is_binary(value) do
    trimmed = value |> String.trim() |> String.downcase()
    if trimmed in @statuses, do: trimmed, else: "all"
  end

  defp inbound_status(_value), do: "all"

  defp inbound_sort(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp inbound_sort(_value), do: nil

  defp normalize_posted(filters, key, fun) do
    if Map.has_key?(filters, key), do: Map.update!(filters, key, fun), else: filters
  end

  defp query_status("all"), do: :all
  defp query_status(status), do: status

  defp companies_path(%ListState{} = state, columns \\ nil) do
    params = ListState.to_params(state)

    query =
      []
      |> maybe_put(:search, Map.get(params, "search"))
      |> maybe_put(:status, status_param(Map.get(params, "status_filter")))
      |> maybe_put(:sort, sort_param(Map.get(params, "sort_by")))
      |> maybe_put(:dir, dir_param(Map.get(params, "sort_dir")))
      |> maybe_put(:page, page_param(Map.get(params, "page")))
      |> maybe_put(:per_page, per_page_param(Map.get(params, "per_page")))

    query = if columns, do: query ++ Enum.to_list(PageColumns.params(columns)), else: query

    case query do
      [] -> ~p"/companies"
      _ -> ~p"/companies?#{query}"
    end
  end

  defp maybe_put(query, _key, nil), do: query
  defp maybe_put(query, key, value), do: query ++ [{key, value}]

  defp status_param("all"), do: nil
  defp status_param(status), do: status

  defp sort_param(@default_sort), do: nil
  defp sort_param(sort), do: sort

  defp dir_param(@default_dir), do: nil
  defp dir_param(dir), do: dir

  defp page_param(1), do: nil
  defp page_param(page), do: page

  defp per_page_param(size) when size == @default_page_size, do: nil
  defp per_page_param(size), do: size

  # The empty row's copy. A search and a status filter are the two ways the
  # person narrowed the list, so the sentence names whichever applies and the
  # recovery undoes exactly that, keeping sort and page size.
  defp filtered?(%ListState{search: search, filters: %{status_filter: status}}) do
    search != "" or status != "all"
  end

  defp cleared(%ListState{} = state) do
    %{state | search: "", page: 1, filters: %{state.filters | status_filter: "all"}}
  end

  defp filtered_empty_title(%ListState{search: search, filters: %{status_filter: status}}) do
    label = if status == "all", do: "", else: "#{status} "
    match = if search == "", do: "", else: " match \u201C#{search}\u201D"
    "No #{label}companies#{match}"
  end

  defp filtered_empty_reason(%ListState{search: search, filters: %{status_filter: status}}) do
    case {search == "", status == "all"} do
      {false, true} ->
        "Check the spelling, or clear the search to see every company in this tenant."

      {true, false} ->
        "No company in this tenant has this status. Show all statuses to see every company."

      {false, false} ->
        "Clear the search and the status filter to see every company in this tenant."
    end
  end

  defp clear_label(%ListState{search: search, filters: %{status_filter: status}}) do
    case {search == "", status == "all"} do
      {false, true} -> "Clear search"
      {true, false} -> "Show all statuses"
      {false, false} -> "Clear search and filter"
    end
  end

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("suspended"), do: :danger
  defp status_badge_kind("pending"), do: :warning
  defp status_badge_kind(_status), do: :neutral

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="companies-index">
        <.header>
          Companies
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin Companies to sidebar"
              context={:inline}
              id="companies-pin"
              data-nav-pin="nav-admin-company"
              aria-pressed="false"
            />
          </:title_actions>
          <:subtitle>Every live company in this tenant</:subtitle>
          <:actions>
            <div class="flex flex-wrap items-center gap-2 sm:gap-3">
              <.button
                :if={allowed?(@current_scope, "admin.company.create")}
                id="companies-add"
                variant="primary"
                navigate={~p"/companies/create"}
              >
                <.icon name="create" class="size-4" /> Add Company
              </.button>
              <.action_link
                id="companies-department-types"
                icon="manage"
                navigate={~p"/companies/department-types"}
                title="Manage department types"
              >
                Department Types
              </.action_link>
              <.action_link
                id="companies-legal-entity-types"
                icon="manage"
                navigate={~p"/companies/legal-entity-types"}
                title="Manage legal entity types"
              >
                Legal Entity Types
              </.action_link>
            </div>
          </:actions>
        </.header>

        <.filter_toolbar id="companies-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="companies-search"
            label="Search companies"
            placeholder="Search by name, code, legal name, email, or jurisdiction..."
          />
          <:control
            type={:select}
            field={@filters_form[:status_filter]}
            id="companies-status-filter"
            label="Status filter"
            options={[
              {"All statuses", "all"},
              {"Active", "active"},
              {"Suspended", "suspended"},
              {"Pending", "pending"},
              {"Archived", "archived"}
            ]}
          />
        </.filter_toolbar>

        <.card id="companies-card" inner_class="p-0">
          <h2 id="companies-table-title" class="sr-only">Companies</h2>


          <div class="p-2">
            <.flex_table
              id="companies"
              columns={@columns.column_views}
              rows={@columns.rows}
              mode={@columns.mode}
              zoom={@columns.view.zoom}
              sort_by={to_string(@index_state.sort_by)}
              sort_dir={PageColumns.sort_dir(@index_state.sort_dir)}
              suggestions={@columns.suggestions}
              add_query={@columns.add_query}
              total={@columns.total}
              expanded={@columns.expanded}
              row_id={&"companies-#{&1}"}
              caption="Companies"
            >
              <:col :let={%{key: id}} id="name">
                <% company = listed(@companies_page, id) %>
              <%!-- The name leads every surface; the legal name is formal
                   detail (#614 identity-line ruling). Display now matches
                   the sort field. --%>
              <.record_link
                workspace={@workspace}
                kind="core/company"
                record_id={company.id}
                navigate={~p"/companies/#{company.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {company.name}
              </.record_link>
              <span
                :if={company.legal_name && company.legal_name != company.name}
                class="block text-xs text-ink-subtle"
              >
                {company.legal_name}
              </span>
            </:col>
              <:col :let={%{key: id}} id="code">
                <% company = listed(@companies_page, id) %>
              <code class="text-xs font-medium tabular-nums">{company.code}</code>
            </:col>
              <:col :let={%{key: id}} id="parent_name">
                <% company = listed(@companies_page, id) %>
              <span class={[is_nil(company.parent_name) && "text-ink-faint"]}>
                {company.parent_name || "None"}
              </span>
            </:col>
              <:col :let={%{key: id}} id="status">
                <% company = listed(@companies_page, id) %>
              <.badge kind={status_badge_kind(company.status)}>
                {company.status}
              </.badge>
            </:col>
              <:col :let={%{key: id}} id="jurisdiction">
                <% company = listed(@companies_page, id) %>
              <span class={[is_nil(company.jurisdiction) && "text-ink-faint"]}>
                {company.jurisdiction || "—"}
              </span>
            </:col>
              <:action :let={%{key: id}}>
                <% company = listed(@companies_page, id) %>
              <div class="flex items-center justify-end gap-3">
                <.badge :if={company.primary?} kind={:neutral}>Primary</.badge>
                <.icon_button
                  icon="view"
                  label={"Open #{company.name}"}
                  navigate={~p"/companies/#{company.id}"}
                />
              </div>
            </:action>
            <%!-- Two different absences, two different sentences: a search or
                 filter that matched nothing offers the way back; a tenant with no
                 companies yet offers the first create to an actor who may make
                 one. --%>
            <:empty
              :if={@companies_page.entries == [] and filtered?(@index_state)}
              title={filtered_empty_title(@index_state)}
              reason={filtered_empty_reason(@index_state)}
            >
              <.button id="companies-clear-search" patch={companies_path(cleared(@index_state), @columns)}>
                {clear_label(@index_state)}
              </.button>
            </:empty>
            <:empty
              :if={@companies_page.entries == [] and not filtered?(@index_state)}
              title="No companies yet"
              reason="Companies created in this tenant appear here."
            >
              <.button
                :if={allowed?(@current_scope, "admin.company.create")}
                id="companies-empty-add"
                variant="primary"
                navigate={~p"/companies/create"}
              >
                <.icon name="create" class="size-4" /> Add Company
              </.button>
            </:empty>
            </.flex_table>
          </div>

          <.pagination
            id="companies-pagination"
            page={@companies_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
