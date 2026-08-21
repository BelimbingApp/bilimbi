defmodule Bilimbi.Core.Company.Web.IndexLive do
  @moduledoc "Tenant-wide company list, via `Bilimbi.Core.Company.list_companies_page/2`."

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Page
  alias Bilimbi.Core.Geonames

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25
  @default_page 1
  @default_sort_by :name
  @default_sort_dir :asc
  @sorts %{
    "name" => :name,
    "status" => :status,
    "jurisdiction" => :jurisdiction
  }
  @status_filters ~w(all active suspended pending)

  defmodule State do
    @moduledoc false
    defstruct search: nil,
              status: "all",
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
     |> assign(:countries, country_lookup())}
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
      |> Map.put(:status, normalize_status(Map.get(filters, "status")))
      |> Map.put(:per_page, normalize_page_size(Map.get(filters, "perPage")))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: companies_path(state))}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: companies_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    state = Map.put(socket.assigns.index_state, :page, normalize_page(page))
    {:noreply, push_patch(socket, to: companies_path(state))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.company.delete") do
      case positive_integer(id) do
        company_id when is_integer(company_id) ->
          delete_company(socket, company_id)

        _invalid ->
          {:noreply, put_flash(socket, :error, "Could not delete company.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to delete companies.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="companies-index">
        <.header>
          Companies
          <:title_actions>
            <button
              type="button"
              id="companies-pin"
              data-nav-pin="nav-admin-company"
              title="Pin Companies to sidebar"
              aria-label="Pin Companies to sidebar"
              aria-pressed="false"
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
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
            <.button
              navigate={~p"/companies/department-types"}
              class="text-xs"
            >
              Department Types
            </.button>
            <.button
              navigate={~p"/companies/legal-entity-types"}
              class="text-xs"
            >
              Legal Entity Types
            </.button>
          </:actions>
        </.header>

        <.card id="companies-card" inner_class="p-0">
          <.form
            for={@filters_form}
            id="companies-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_minmax(11rem,14rem)]">
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
                  placeholder="Search by name, code, legal name, email, jurisdiction..."
                  class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
                />
              </div>
              <.input
                field={@filters_form[:status]}
                id="companies-status-filter"
                type="select"
                label="Status filter"
                label_class="sr-only"
                wrapper_class="mb-0"
                options={status_options()}
              />
            </div>
          </.form>

          <.table
            id="companies"
            rows={@companies_page.entries}
            row_id={fn company -> "company-#{company.id}" end}
            caption="Companies"
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
          >
            <:col :let={company} label="Name" sort="name" sort_id="companies-sort-name">
              <.link
                navigate={~p"/companies/#{company.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {display_name(company)}
              </.link>
              <.badge :if={company.is_primary} kind={:neutral} class="ml-2">Primary</.badge>
              <span
                :if={company.legal_name && company.legal_name != company.name}
                class="block text-xs text-ink-subtle"
              >
                {company.name}
              </span>
            </:col>
            <:col :let={company} label="Code">
              <code class="text-xs font-medium">{company.code}</code>
            </:col>
            <:col :let={company} label="Status" sort="status" sort_id="companies-sort-status">
              <.badge kind={status_badge_kind(company.status)}>
                {String.capitalize(company.status)}
              </.badge>
            </:col>
            <:col :let={company} label="Parent">
              <span :if={company.parent_name}>{company.parent_name}</span>
              <span :if={is_nil(company.parent_name)} class="text-ink-subtle">—</span>
            </:col>
            <:col
              :let={company}
              label="Jurisdiction"
              sort="jurisdiction"
              sort_id="companies-sort-jurisdiction"
            >
              {country_name(company.jurisdiction, @countries)}
            </:col>
            <:action :let={company}>
              <div class="flex items-center justify-end gap-3">
                <.link
                  navigate={~p"/companies/#{company.id}"}
                  class="text-xs font-medium text-action hover:underline"
                >
                  Open
                </.link>
                <button
                  :if={allowed?(@current_scope, "admin.company.delete") and not company.is_primary}
                  id={"company-#{company.id}-delete"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={company.id}
                  data-confirm={"Are you sure you want to delete #{display_name(company)}?"}
                  title="Delete company"
                  class="rounded-md border border-danger-line bg-danger-surface px-2.5 py-1.5 text-xs font-semibold text-danger-ink transition hover:bg-danger"
                >
                  Delete
                </button>
              </div>
            </:action>
            <:empty :if={@companies_page.entries == []}>
              No companies found in this workspace.
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

  defp load_page(socket, %State{} = state) do
    page =
      Company.list_companies_page(socket.assigns.current_scope.scope,
        page: state.page,
        page_size: state.per_page,
        search: state.search,
        status: status_filter_value(state.status),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      )

    cond do
      page.total_pages > 0 and state.page > page.total_pages ->
        push_patch(socket, to: companies_path(%{state | page: page.total_pages}))

      page.total_pages == 0 and state.page > 1 ->
        push_patch(socket, to: companies_path(%{state | page: 1}))

      true ->
        socket
        |> assign(:index_state, state)
        |> assign(:companies_page, page)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
    end
  end

  defp delete_company(socket, company_id) do
    case Company.delete_company(socket.assigns.current_scope.scope, company_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Company deleted.")
         |> load_page(socket.assigns.index_state)}

      {:error, :primary_company} ->
        {:noreply, put_flash(socket, :error, "Transfer the primary company before deleting it.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That company no longer exists.")
         |> load_page(socket.assigns.index_state)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete company.")}
    end
  end

  defp empty_page do
    %Page{
      entries: [],
      page: @default_page,
      page_size: @default_page_size,
      total_entries: 0,
      total_pages: 0
    }
  end

  defp state_from_params(params) do
    %State{
      search: normalize_search(params["search"] || params["q"]),
      status: normalize_status(params["status"]),
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
      trimmed -> trimmed
    end
  end

  defp normalize_status(value) when is_binary(value) do
    value = String.downcase(String.trim(value))
    if value in @status_filters, do: value, else: "all"
  end

  defp normalize_status(_value), do: "all"

  defp normalize_sort_by(value) when is_binary(value) do
    Map.get(@sorts, String.downcase(String.trim(value)), @default_sort_by)
  end

  defp normalize_sort_by(_value), do: @default_sort_by

  defp normalize_sort_dir(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "desc" -> :desc
      _ -> :asc
    end
  end

  defp normalize_sort_dir(_value), do: @default_sort_dir

  defp normalize_page(value) do
    positive_integer(value) || @default_page
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
      "status" => state.status,
      "perPage" => to_string(state.per_page)
    }
  end

  defp companies_path(state) do
    search_val = if state.search not in [nil, ""], do: state.search
    status_val = if state.status != "all", do: state.status
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

  defp status_filter_value("all"), do: nil
  defp status_filter_value(status), do: status

  defp status_options do
    [
      {"All statuses", "all"},
      {"Active", "active"},
      {"Suspended", "suspended"},
      {"Pending", "pending"}
    ]
  end

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("suspended"), do: :warning
  defp status_badge_kind("pending"), do: :neutral
  defp status_badge_kind(_status), do: :neutral

  defp display_name(company) do
    if present?(company.legal_name), do: company.legal_name, else: company.name
  end

  defp country_name(nil, _countries), do: "—"
  defp country_name("", _countries), do: "—"
  defp country_name(iso, countries), do: Map.get(countries, iso, iso)

  defp country_lookup do
    Geonames.list_countries()
    |> Map.new(&{&1.iso, "#{&1.country} (#{&1.iso})"})
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
