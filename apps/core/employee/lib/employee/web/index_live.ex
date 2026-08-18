defmodule Bilimbi.Core.Employee.Web.IndexLive do
  @moduledoc """
  Employees for the signed-in company, via `Bilimbi.Core.Employee.list_employees/2`.

  There is no tenant-wide employee list. Affiliation is company-scoped.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Employee

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    case Employee.list_employees(scope, company_id) do
      {:ok, employees} ->
        {:ok,
         socket
         |> assign(:page_title, "Employees")
         |> assign(:active_nav, "admin.employee")
         |> assign(:company_id, company_id)
         |> assign(:employees_count, length(employees))
         |> stream(:employees, employees)}

      {:error, :company_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That company is not in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

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
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
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
          <.table
            id="employees"
            rows={@streams.employees}
            row_id={fn {id, _employee} -> id end}
            row_item={fn {_id, employee} -> employee end}
            framed={false}
          >
            <:col :let={employee} label="Name">
              <.link
                navigate={~p"/employees/#{employee.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {Employee.Summary.display_name(employee)}
              </.link>

              <span :if={employee.designation} class="block text-xs text-ink-subtle">
                {employee.designation}
              </span>
            </:col>

            <:col :let={employee} label="No.">
              <code class="text-xs font-medium">{employee.employee_number}</code>
            </:col>

            <:col :let={employee} label="Type">{employee.employee_type}</:col>

            <:col :let={employee} label="Status">
              <.badge kind={if employee.status == "active", do: :success, else: :neutral}>
                {employee.status}
              </.badge>
            </:col>

            <:empty :if={@employees_count == 0}>
              No employees found.
            </:empty>
          </.table>
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
