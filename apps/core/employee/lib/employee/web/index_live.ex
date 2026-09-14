defmodule Bilimbi.Core.Employee.Web.IndexLive do
  @moduledoc """
  Employees for the signed-in company, via `Bilimbi.Core.Employee.list_administration_page/3`.

  There is no tenant-wide employee list. Affiliation is company-scoped.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.AdministrationPage

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25
  @sorts %{
    "name" => :full_name,
    "full_name" => :full_name,
    "type" => :employee_type_label,
    "employee_type" => :employee_type_label,
    "employee_type_label" => :employee_type_label,
    "status" => :status
  }
  @type_filters %{
    "all" => :all,
    "human" => :human,
    "agent" => :agent
  }
  @default_sort_by :full_name
  @default_sort_dir :asc
  @default_page 1

  defmodule State do
    @moduledoc false
    defstruct search: nil,
              type_filter: :all,
              sort_by: :full_name,
              sort_dir: :asc,
              page: 1,
              per_page: 25
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Employees")
     |> assign(:active_nav, "admin.employee")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:index_state, %State{})
     |> assign(:employees_page, empty_page())
     |> assign(:department_map, %{})
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
      |> Map.put(:type_filter, normalize_type_filter(Map.get(filters, "type_filter")))
      |> Map.put(:per_page, normalize_page_size(Map.get(filters, "perPage")))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: employees_path(state))}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: employees_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    target_page =
      case positive_integer(page) do
        n when is_integer(n) -> n
        _ -> 1
      end

    state = Map.put(socket.assigns.index_state, :page, target_page)
    {:noreply, push_patch(socket, to: employees_path(state))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.employee.delete") do
      scope = resolve_scope(socket)
      company_id = resolve_company_id(socket)

      case positive_integer(id) do
        employee_id when is_integer(employee_id) ->
          case Employee.delete_employee(scope, company_id, employee_id) do
            :ok ->
              socket =
                socket
                |> put_flash(:info, "Employee deleted successfully.")
                |> load_page(socket.assigns.index_state)

              {:noreply, socket}

            {:error, :employee_not_found} ->
              socket =
                socket
                |> put_flash(:error, "That employee no longer exists.")
                |> load_page(socket.assigns.index_state)

              {:noreply, socket}

            {:error, _reason} ->
              {:noreply, put_flash(socket, :error, "Failed to delete employee.")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to delete employee.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to delete employees.")}
    end
  end

  defp load_page(socket, state) do
    scope = resolve_scope(socket)
    company_id = resolve_company_id(socket)

    options = [
      page: state.page,
      page_size: state.per_page,
      search: state.search,
      type_filter: state.type_filter,
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Employee.list_administration_page(scope, company_id, options) do
      {:ok, %AdministrationPage{total_pages: total_pages}}
      when total_pages > 0 and state.page > total_pages ->
        clamped_state = %{state | page: total_pages}
        push_patch(socket, to: employees_path(clamped_state))

      {:ok, %AdministrationPage{total_pages: 0}} when state.page > 1 ->
        clamped_state = %{state | page: 1}
        push_patch(socket, to: employees_path(clamped_state))

      {:ok, %AdministrationPage{} = page} ->
        socket
        |> assign(:index_state, state)
        |> assign(:employees_page, page)
        |> assign(:department_map, department_map(scope, company_id))
        |> assign(:company_id, company_id)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
        |> stream(:employees, page.entries, reset: true)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load employees.")
        |> assign(:index_state, state)
        |> assign(:employees_page, empty_page())
        |> stream(:employees, [], reset: true)
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

  # Department names come through Company's public API, same as the show
  # page — the departments table belongs to Core Company, not this module.
  defp department_map(scope, company_id) do
    case Company.list_departments(scope, company_id) do
      {:ok, departments} ->
        Map.new(departments, fn dept ->
          {dept.id, if(dept.type, do: dept.type.name, else: "Department #{dept.id}")}
        end)

      _ ->
        %{}
    end
  end

  defp resolve_scope(socket) do
    socket.assigns.current_scope.scope
  end

  defp resolve_company_id(socket) do
    socket.assigns.current_scope.user["company_id"]
  end

  defp state_from_params(params) do
    %State{
      search: normalize_search(params["search"] || params["q"]),
      type_filter: normalize_type_filter(params["type"] || params["type_filter"]),
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

  defp normalize_type_filter(nil), do: :all

  defp normalize_type_filter(value) when is_binary(value) do
    Map.get(@type_filters, String.downcase(String.trim(value)), :all)
  end

  defp normalize_type_filter(value) when is_atom(value), do: value
  defp normalize_type_filter(_value), do: :all

  defp normalize_sort_by(nil), do: @default_sort_by

  defp normalize_sort_by(value) when is_binary(value) do
    Map.get(@sorts, String.downcase(String.trim(value)), @default_sort_by)
  end

  defp normalize_sort_by(_value), do: @default_sort_by

  defp normalize_sort_dir(nil), do: @default_sort_dir

  defp normalize_sort_dir(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "desc" -> :desc
      _ -> :asc
    end
  end

  defp normalize_sort_dir(_value), do: @default_sort_dir

  defp normalize_page(value) do
    case positive_integer(value) do
      page when is_integer(page) -> page
      _ -> @default_page
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
    field = Map.get(@sorts, sort_key, :full_name)

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
      "type_filter" => to_string(state.type_filter),
      "perPage" => to_string(state.per_page)
    }
  end

  defp employees_path(state) do
    search_val = if state.search not in [nil, ""], do: state.search
    type_val = if state.type_filter != :all, do: to_string(state.type_filter)
    sort_val = if state.sort_by != :full_name, do: to_string(state.sort_by)
    dir_val = if state.sort_dir != :asc, do: to_string(state.sort_dir)
    page_val = if state.page != @default_page, do: state.page
    per_page_val = if state.per_page != @default_page_size, do: state.per_page

    params =
      []
      |> maybe_put(:search, search_val)
      |> maybe_put(:type, type_val)
      |> maybe_put(:sort, sort_val)
      |> maybe_put(:dir, dir_val)
      |> maybe_put(:page, page_val)
      |> maybe_put(:per_page, per_page_val)

    case params do
      [] -> ~p"/employees"
      _ -> ~p"/employees?#{params}"
    end
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: params ++ [{key, value}]

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("probation"), do: :warning
  defp status_badge_kind("terminated"), do: :danger
  defp status_badge_kind(_status), do: :neutral

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="employees-index">
        <.header>
          Employees
          <:title_actions>
            <button
              type="button"
              id="employees-pin"
              data-nav-pin="nav-admin-employee"
              title="Pin Employees to sidebar"
              aria-label="Pin Employees to sidebar"
              aria-pressed="false"
              class="grid size-6 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:subtitle>People employed by {@current_scope.user["company_name"]}</:subtitle>

          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.employee-type.list")}
              navigate={~p"/employee-types"}
              id="employee-types"
            >
              Employee Types
            </.button>

            <.button
              :if={allowed?(@current_scope, "admin.employee.create")}
              id="employee-new"
              navigate={~p"/employees/new"}
              variant="primary"
            >
              New Employee
            </.button>
          </:actions>
        </.header>

        <.card id="employees-card" inner_class="p-0">
          <h2 id="employees-table-title" class="sr-only">Employees</h2>
          <.form
            for={@filters_form}
            id="employees-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_minmax(12rem,16rem)]">
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
                />
                <.input
                  field={@filters_form[:search]}
                  id="employees-search"
                  type="search"
                  phx-debounce="300"
                  maxlength="255"
                  label="Search employees"
                  label_class="sr-only"
                  wrapper_class="mb-0"
                  placeholder="Search by name, employee number, email, designation, or job description..."
                  class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
                />
              </div>
              <.input
                field={@filters_form[:type_filter]}
                id="employees-type-filter"
                type="select"
                label="Type filter"
                label_class="sr-only"
                wrapper_class="mb-0"
                options={[
                  {"All types", "all"},
                  {"Human only", "human"},
                  {"Agent only", "agent"}
                ]}
              />
            </div>
          </.form>

          <.table
            id="employees"
            rows={@streams.employees}
            row_id={fn {id, _employee} -> id end}
            row_item={fn {_id, employee} -> employee end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
          >
            <:col :let={employee} label="Name" sort="full_name" sort_id="employees-sort-name">
              <.link
                navigate={~p"/employees/#{employee.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {employee.full_name}
              </.link>

              <span :if={employee.designation} class="block text-xs text-ink-subtle">
                {employee.designation}
              </span>
            </:col>

            <:col :let={employee} label="No.">
              <code class="text-xs font-medium tabular-nums">{employee.employee_number}</code>
            </:col>

            <:col :let={employee} label="Department">
              <span class={[is_nil(employee.department_id) && "text-ink-faint"]}>
                {Map.get(@department_map, employee.department_id, "—")}
              </span>
            </:col>

            <:col
              :let={employee}
              label="Type"
              sort="employee_type_label"
              sort_id="employees-sort-type"
            >
              <.badge kind={:neutral}>
                {employee.employee_type_label || employee.employee_type}
              </.badge>
            </:col>

            <:col :let={employee} label="Status" sort="status" sort_id="employees-sort-status">
              <.badge kind={status_badge_kind(employee.status)}>
                {employee.status}
              </.badge>
            </:col>

            <:action :let={employee}>
              <div class="flex items-center justify-end gap-3">
                <.link
                  :if={allowed?(@current_scope, "admin.employee.update")}
                  id={"employee-#{employee.id}-edit"}
                  navigate={~p"/employees/#{employee.id}/edit"}
                  class="text-xs font-semibold text-action hover:underline"
                >
                  Edit
                </.link>
                <button
                  :if={allowed?(@current_scope, "admin.employee.delete")}
                  id={"employee-#{employee.id}-delete"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={employee.id}
                  data-confirm={"Are you sure you want to delete #{employee.full_name}?"}
                  title="Delete employee"
                  class="rounded-md border border-danger-line bg-danger-surface px-2.5 py-1.5 text-xs font-semibold text-danger-ink transition hover:bg-danger"
                >
                  Delete
                </button>
              </div>
            </:action>

            <:empty :if={@employees_page.entries == []}>
              No employees found.
            </:empty>
          </.table>

          <.pagination
            id="employees-pagination"
            page={@employees_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
