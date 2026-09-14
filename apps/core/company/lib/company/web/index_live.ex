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
     |> assign(:filters_form, to_form(filters_form_params(%State{}), as: :filters))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = state_from_params(params)
    {:noreply, load_page(socket, state)}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", socket.assigns.index_state.search))
      |> Map.put(:status_filter, normalize_status_filter(Map.get(filters, "status_filter")))
      |> Map.put(:per_page, normalize_page_size(Map.get(filters, "perPage")))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: companies_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: companies_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    target_page =
      case positive_integer(page) do
        nil -> @default_page
        value -> value
      end

    state = Map.put(socket.assigns.index_state, :page, target_page)
    {:noreply, push_patch(socket, to: companies_path(state))}
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
        push_patch(socket, to: companies_path(clamped_state))

      {:ok, %AdministrationPage{total_pages: 0}} when state.page > 1 ->
        clamped_state = %{state | page: 1}
        push_patch(socket, to: companies_path(clamped_state))

      {:ok, %AdministrationPage{} = page} ->
        socket
        |> assign(:index_state, state)
        |> assign(:companies_page, page)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
        |> stream(:companies, page.entries, reset: true)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load companies.")
        |> assign(:index_state, state)
        |> assign(:companies_page, empty_page())
        |> stream(:companies, [], reset: true)
    end
  end

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

  defp companies_path(state) do
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

    case params do
      [] -> ~p"/companies"
      _ -> ~p"/companies?#{params}"
    end
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: params ++ [{key, value}]

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
            <.button
              :if={allowed?(@current_scope, "admin.company.create")}
              id="companies-add"
              variant="primary"
              navigate={~p"/companies/create"}
            >
              <.icon name="hero-plus" class="size-4" /> Add Company
            </.button>
            <.button navigate={~p"/companies/department-types"} class="text-xs">
              Department Types
            </.button>
            <.button navigate={~p"/companies/legal-entity-types"} class="text-xs">
              Legal Entity Types
            </.button>
          </:actions>
        </.header>

        <.form for={@filters_form} id="companies-filters" phx-change="filters" class="mb-2">
          <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_minmax(10rem,13rem)]">
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
              />
              <.input
                field={@filters_form[:search]}
                id="companies-search"
                type="search"
                phx-debounce="300"
                maxlength="255"
                label="Search companies"
                label_class="sr-only"
                wrapper_class="mb-0"
                placeholder="Search by name, code, legal name, email, or jurisdiction..."
                class="block w-full rounded-md border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/30"
              />
            </div>
            <.input
              field={@filters_form[:status_filter]}
              id="companies-status-filter"
              type="select"
              label="Status filter"
              label_class="sr-only"
              wrapper_class="mb-0"
              options={[
                {"All statuses", "all"},
                {"Active", "active"},
                {"Suspended", "suspended"},
                {"Pending", "pending"},
                {"Archived", "archived"}
              ]}
            />
          </div>
        </.form>

        <.card id="companies-card" inner_class="p-0">
          <h2 id="companies-table-title" class="sr-only">Companies</h2>


          <.table
            id="companies"
            rows={@streams.companies}
            row_id={fn {id, _company} -> id end}
            row_item={fn {_id, company} -> company end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
          >
            <:col :let={company} label="Name" sort="name" sort_id="companies-sort-name">
              <%!-- The name leads every surface; the legal name is formal
                   detail (#614 identity-line ruling). Display now matches
                   the sort field. --%>
              <.link
                navigate={~p"/companies/#{company.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {company.name}
              </.link>
              <span
                :if={company.legal_name && company.legal_name != company.name}
                class="block text-xs text-ink-subtle"
              >
                {company.legal_name}
              </span>
            </:col>

            <:col :let={company} label="Code">
              <code class="text-xs font-medium tabular-nums">{company.code}</code>
            </:col>

            <:col :let={company} label="Parent">
              <span class={[is_nil(company.parent_name) && "text-ink-faint"]}>
                {company.parent_name || "None"}
              </span>
            </:col>

            <:col :let={company} label="Status" sort="status" sort_id="companies-sort-status">
              <.badge kind={status_badge_kind(company.status)}>
                {company.status}
              </.badge>
            </:col>

            <:col
              :let={company}
              label="Jurisdiction"
              sort="jurisdiction"
              sort_id="companies-sort-jurisdiction"
            >
              <span class={[is_nil(company.jurisdiction) && "text-ink-faint"]}>
                {company.jurisdiction || "—"}
              </span>
            </:col>

            <:action :let={company}>
              <div class="flex items-center justify-end gap-3">
                <.badge :if={company.primary?} kind={:neutral}>Primary</.badge>
                <.icon_button
                  icon="hero-eye"
                  label={"Open #{company.name}"}
                  navigate={~p"/companies/#{company.id}"}
                />
              </div>
            </:action>

            <:empty :if={@companies_page.entries == []}>
              No companies found.
            </:empty>
          </.table>

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
