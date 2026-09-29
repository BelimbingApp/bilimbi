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
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.AdministrationPage

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25
  @sorts %{
    "name" => :name,
    "status" => :status,
    "jurisdiction" => :jurisdiction
  }
  @status_filters ["active", "suspended", "pending", "archived"]
  @default_sort_by :name
  @default_sort_dir :asc
  @default_page 1

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

  defmodule State do
    @moduledoc false
    defstruct search: nil,
              status_filter: :all,
              sort_by: :name,
              sort_dir: :asc,
              page: 1,
              per_page: 25
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Companies")
     |> assign(:active_nav, "admin.company")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:index_state, %State{})
     |> assign(:companies_page, empty_page())
     |> assign(:filters_form, to_form(filters_form_params(%State{}), as: :filters))
     |> assign(
       :columns,
       PageColumns.mount(socket.assigns.current_scope.scope, "companies", @builtins)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = state_from_params(params)
    columns = PageColumns.from_params(socket.assigns.columns, params)
    {:noreply, socket |> assign(:columns, columns) |> load_page(state)}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", socket.assigns.index_state.search))
      |> Map.put(:status_filter, normalize_status_filter(Map.get(filters, "status_filter")))
      |> Map.put(:per_page, normalize_page_size(Map.get(filters, "perPage")))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: companies_path(state, socket.assigns.columns))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket,
       to: companies_path(next_sort(socket.assigns.index_state, sort_by), socket.assigns.columns)
     )}
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

  def handle_event("page", %{"page" => page}, socket) do
    target_page =
      case positive_integer(page) do
        nil -> @default_page
        value -> value
      end

    state = Map.put(socket.assigns.index_state, :page, target_page)
    {:noreply, push_patch(socket, to: companies_path(state, socket.assigns.columns))}
  end

  defp load_page(socket, state) do
    scope = socket.assigns.current_scope.scope

    options = [
      page: state.page,
      page_size: state.per_page,
      search: state.search || "",
      status_filter: state.status_filter,
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Company.list_administration_page(scope, options) do
      {:ok, %AdministrationPage{total_pages: total_pages}}
      when total_pages > 0 and state.page > total_pages ->
        clamped_state = %{state | page: total_pages}
        push_patch(socket, to: companies_path(clamped_state, socket.assigns.columns))

      {:ok, %AdministrationPage{total_pages: 0}} when state.page > 1 ->
        clamped_state = %{state | page: 1}
        push_patch(socket, to: companies_path(clamped_state, socket.assigns.columns))

      {:ok, %AdministrationPage{} = page} ->
        socket
        |> assign(:index_state, state)
        |> assign(:companies_page, page)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
        |> assign(
          :columns,
          PageColumns.load(socket.assigns.columns, page.entries, & &1.id, &builtin_cells/1)
        )

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

  defp state_from_params(params) do
    %State{
      search: normalize_search(params["search"] || params["q"]),
      status_filter: normalize_status_filter(params["status"] || params["status_filter"]),
      sort_by: normalize_sort_by(params["sort"]),
      sort_dir: normalize_sort_dir(params["dir"]),
      page: normalize_page(params["page"]),
      per_page: normalize_page_size(params["per_page"] || params["perPage"])
    }
  end

  defp normalize_search(nil), do: nil

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 255)
    end
  end

  defp normalize_search(_value), do: nil

  defp normalize_status_filter(value) when is_binary(value) do
    trimmed = value |> String.trim() |> String.downcase()
    if trimmed in @status_filters, do: trimmed, else: :all
  end

  defp normalize_status_filter(value) when value in [:all | @status_filters], do: value
  defp normalize_status_filter(_value), do: :all

  defp normalize_sort_by(value) when is_binary(value),
    do: Map.get(@sorts, String.downcase(String.trim(value)), @default_sort_by)

  defp normalize_sort_by(_value), do: @default_sort_by

  defp normalize_sort_dir("desc"), do: :desc
  defp normalize_sort_dir(:desc), do: :desc
  defp normalize_sort_dir(_value), do: @default_sort_dir

  defp normalize_page(value) do
    case positive_integer(value) do
      nil -> @default_page
      page -> page
    end
  end

  defp normalize_page_size(value) do
    case positive_integer(value) do
      size when size in @page_sizes -> size
      _ -> @default_page_size
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp next_sort(state, sort_key) do
    field = Map.get(@sorts, sort_key, @default_sort_by)

    if state.sort_by == field do
      %{state | sort_dir: toggle_sort_dir(state.sort_dir), page: 1}
    else
      %{state | sort_by: field, sort_dir: :asc, page: 1}
    end
  end

  defp toggle_sort_dir(:asc), do: :desc
  defp toggle_sort_dir(:desc), do: :asc

  defp filters_form_params(state) do
    %{
      "search" => state.search || "",
      "status_filter" => to_string(state.status_filter),
      "perPage" => to_string(state.per_page)
    }
  end

  defp companies_path(state, columns \\ nil) do
    search_val = if state.search not in [nil, ""], do: state.search
    status_val = if state.status_filter != :all, do: to_string(state.status_filter)
    sort_val = if state.sort_by != @default_sort_by, do: to_string(state.sort_by)
    dir_val = if state.sort_dir != @default_sort_dir, do: to_string(state.sort_dir)
    page_val = if state.page != @default_page, do: state.page
    per_page_val = if state.per_page != @default_page_size, do: state.per_page

    params =
      []
      |> maybe_put(:search, search_val)
      |> maybe_put(:status, status_val)
      |> maybe_put(:sort, sort_val)
      |> maybe_put(:dir, dir_val)
      |> maybe_put(:page, page_val)
      |> maybe_put(:per_page, per_page_val)

    params = if columns, do: params ++ Enum.to_list(PageColumns.params(columns)), else: params

    case params do
      [] -> ~p"/companies"
      _ -> ~p"/companies?#{params}"
    end
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: params ++ [{key, value}]

  # The empty row's copy. A search and a status filter are the two ways the
  # person narrowed the list, so the sentence names whichever applies and the
  # recovery undoes exactly that, keeping sort and page size.
  defp filtered?(%State{search: search, status_filter: status_filter}) do
    search not in [nil, ""] or status_filter != :all
  end

  defp cleared(%State{} = state), do: %{state | search: nil, status_filter: :all, page: 1}

  defp filtered_empty_title(%State{search: search, status_filter: status_filter}) do
    status = if status_filter == :all, do: "", else: "#{status_filter} "
    match = if search in [nil, ""], do: "", else: " match \u201C#{search}\u201D"
    "No #{status}companies#{match}"
  end

  defp filtered_empty_reason(%State{search: search, status_filter: status_filter}) do
    case {search in [nil, ""], status_filter == :all} do
      {false, true} ->
        "Check the spelling, or clear the search to see every company in this tenant."

      {true, false} ->
        "No company in this tenant has this status. Show all statuses to see every company."

      {false, false} ->
        "Clear the search and the status filter to see every company in this tenant."
    end
  end

  defp clear_label(%State{search: search, status_filter: status_filter}) do
    case {search in [nil, ""], status_filter == :all} do
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
            <div class="flex items-center gap-3">
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
              <.button id="companies-clear-search" patch={companies_path(cleared(@index_state))}>
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
