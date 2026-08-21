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

  alias Bilimbi.Core.Employee

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> reload()}
  end

  # Deliberately strict, matching the address panel (#409): the company page
  # resolved this company before rendering the panel, so a non-ok here is
  # infrastructure failure or a mid-session deletion — raising reaches the
  # recovery boundary instead of rendering a broken section as an empty one.
  defp reload(socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company_id
    {:ok, employees} = Employee.list_employees(scope, company_id)
    assign(socket, :employees, employees)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="mt-6">
      <div class="flex items-center gap-2 mb-2">
        <h2 class="text-sm font-semibold text-ink-strong">Employees</h2>
        <.badge>{length(@employees)}</.badge>
      </div>
      <.table
        id="company-employees-table"
        rows={@employees}
        row_id={fn employee -> "company-employee-#{employee.id}" end}
        row_item={fn employee -> employee end}
        caption="Employees"
      >
        <:col :let={employee} label="Name">
          <span class="font-medium">{employee.full_name}</span>
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
        <:empty :if={@employees == []}>
          No employees found for this company.
        </:empty>
      </.table>
    </section>
    """
  end
end
