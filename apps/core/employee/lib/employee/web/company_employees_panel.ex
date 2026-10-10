defmodule Bilimbi.Core.Employee.Web.CompanyEmployeesPanel do
  @moduledoc """
  Company-page employees panel, contributed as a discovered embed.

  Core Employee owns the employee read; the company page renders it by the
  `"company.employees"` manifest key and never names this module (#570/#595).
  Ported behaviour-for-behaviour from the company show page's former inline
  Employees section, which reached `Employee.list_employees/2` through a
  `Code.ensure_loaded?` + `function_exported?` probe.

  The panel is read-only and carries no capability of its own: the company
  route already gates on `admin.company.view`, and this list is the same
  informational content the section rendered unconditionally before. There is
  no write here, so `<.discovered_panel>` renders it for anyone who reaches the
  company page and `dispatch/3` is never involved.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.Employee

  @page_sizes [25, 50, 100, 300]

  @builtins [
    %{
      id: "full_name",
      label: "Name",
      sort: "full_name",
      sort_id: "company-employees-sort-full-name"
    },
    %{
      id: "employee_number",
      label: "No.",
      sort: "employee_number",
      sort_id: "company-employees-sort-employee-number"
    },
    %{
      id: "employee_type",
      label: "Type",
      sort: "employee_type",
      sort_id: "company-employees-sort-employee-type"
    },
    %{id: "status", label: "Status", sort: "status", sort_id: "company-employees-sort-status"}
  ]

  @write_guard_opt_out ~w(employees_grid)

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:columns, fn -> ListColumns.mount("company-employees", @builtins) end)
     |> reload()}
  end

  @impl true
  def handle_event("employees_grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      _outcome -> {:noreply, socket}
    end
  end

  # Deliberately strict, matching the address panel (#409): the company page
  # resolved this company before rendering the panel, so a non-ok here is
  # infrastructure failure or a mid-session deletion — raising reaches the
  # recovery boundary instead of rendering a broken section as an empty one.
  defp reload(socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company_id
    table_state = socket.assigns.table_state
    page_sizes = socket.assigns[:page_sizes] || @page_sizes
    {:ok, employees} = Employee.list_employees(scope, company_id)
    employees_page = employees |> filter_and_sort(table_state) |> ListState.paginate(table_state)

    socket
    |> assign(:employees, employees)
    |> assign(:employees_count, length(employees))
    |> assign(:employees_page, employees_page)
    |> assign(:columns, ListColumns.load(socket.assigns.columns, employees_page.entries, & &1.id))
    |> assign(:page_sizes, page_sizes)
    |> assign(:filters_form, ListState.filters_form(table_state, as: :employees_filters))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="contents">
      <.card class="mt-6" inner_class="p-0">
        <div class="p-4 pb-2">
          <div class="mb-4 flex items-center gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              Employees
            </h3>
            <.badge>{@employees_count}</.badge>
          </div>
          <.form
            for={@filters_form}
            id="company-employees-filters"
            phx-change="employees_filters"
            class="mb-2"
          >
            <div class="relative">
              <.icon
                name="search"
                class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
              />
              <.input
                field={@filters_form[:search]}
                id="company-employees-search"
                type="search"
                phx-debounce="300"
                maxlength="255"
                label="Search employees"
                label_class="sr-only"
                wrapper_class="mb-0"
                placeholder="Search by name, employee number, email, designation..."
                class="block w-full rounded-md border border-high-contrast-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/30 disabled:cursor-not-allowed disabled:bg-surface-sunken disabled:text-ink-subtle"
              />
            </div>
          </.form>
        </div>
        <.flex_table
          id="company-employees-table"
          columns={@columns.column_views}
          rows={@columns.rows}
          mode={@columns.mode}
          zoom={@columns.zoom}
          suggestions={@columns.suggestions}
          add_query={@columns.add_query}
          row_id={&"company-employee-#{&1}"}
          event="employees_grid"
          target={@myself}
          sort_by={@table_state.sort_by}
          sort_dir={@table_state.sort_dir}
          sort_event="employees_sort"
          caption="Employees"
          framed={false}
        >
          <:col
            :let={%{record: employee}}
            id="full_name"
          >
            <span class="font-medium">{employee.full_name}</span>
            <span
              :if={@columns.mode == :normal and not is_nil(employee.designation)}
              class="block text-xs text-ink-subtle"
            >
              {employee.designation}
            </span>
          </:col>
          <:col
            :let={%{record: employee}}
            id="employee_number"
          >
            <code class="text-xs font-medium">{employee.employee_number}</code>
          </:col>
          <:col
            :let={%{record: employee}}
            id="employee_type"
          >
            {employee.employee_type_label || employee.employee_type}
          </:col>
          <:col :let={%{record: employee}} id="status">
            <.badge kind={if employee.status == "active", do: :success, else: :neutral}>
              {employee.status}
            </.badge>
          </:col>
          <:empty :if={@employees_page.total_entries == 0}>
            No employees found for this company.
          </:empty>
        </.flex_table>
        <.pagination
          id="company-employees-pagination"
          page={@employees_page}
          page_sizes={@page_sizes}
          filters_form={@filters_form}
          filters_event="employees_filters"
          page_event="employees_page"
        />
      </.card>
    </div>
    """
  end

  # The company page parses the URL once and passes the `ListState`; this
  # panel only filters and sorts the rows it listed, and `ListState.paginate/2`
  # slices them.
  defp filter_and_sort(employees, state) do
    search = state.search |> String.trim() |> String.downcase()

    sorted =
      employees
      |> Enum.filter(&matches_search?(&1, search))
      |> Enum.sort_by(&sort_value(&1, state.sort_by))

    if state.sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp matches_search?(_employee, ""), do: true

  defp matches_search?(employee, search) do
    [
      employee.full_name,
      employee.short_name,
      employee.employee_number,
      employee.employee_type,
      employee.employee_type_label,
      employee.designation,
      employee.email,
      employee.status
    ]
    |> Enum.any?(fn value ->
      value
      |> to_string()
      |> String.downcase()
      |> String.contains?(search)
    end)
  end

  defp sort_value(employee, :full_name), do: sort_string(employee.full_name)
  defp sort_value(employee, :employee_number), do: sort_string(employee.employee_number)

  defp sort_value(employee, :employee_type),
    do: sort_string(employee.employee_type_label || employee.employee_type)

  defp sort_value(employee, :status), do: sort_string(employee.status)

  defp sort_string(nil), do: ""
  defp sort_string(value), do: value |> to_string() |> String.downcase()
end
