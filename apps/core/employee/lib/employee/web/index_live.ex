defmodule Bilimbi.Core.Employee.Web.IndexLive do
  @moduledoc """
  Employees for the signed-in company, via `Bilimbi.Core.Employee.list_employees/2`.

  There is no tenant-wide employee list. Affiliation is company-scoped.
  """

  use Bilimbi.Base.UI, :live_view

  import Bilimbi.Core.Employee.Web.Capabilities, only: [allowed?: 2]

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
      <div class="mx-auto max-w-4xl">
        <.header>
          Employees
          <:subtitle>People employed by {@current_scope.user["company_name"]}</:subtitle>

          <:actions>
            <.link
              :if={allowed?(@current_scope, "admin.employee-type.list")}
              navigate={~p"/employee-types"}
              id="employee-types"
              class="rounded-md px-2.5 py-1.5 text-xs font-medium text-ink-muted ring-1 ring-line transition hover:bg-surface-sunken hover:text-ink"
            >
              Employee types
            </.link>

            <.button
              :if={allowed?(@current_scope, "admin.employee.create")}
              id="employee-new"
              navigate={~p"/employees/new"}
              variant="primary"
            >
              New employee
            </.button>
          </:actions>
        </.header>

        <div class="mt-5">
          <.table id="employees" rows={@streams.employees}>
            <:col :let={{_id, employee}} label="Name">
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

            <:col :let={{_id, employee}} label="No.">
              <code class="text-xs font-medium">{employee.employee_number}</code>
            </:col>

            <:col :let={{_id, employee}} label="Type">{employee.employee_type}</:col>

            <:col :let={{_id, employee}} label="Status">
              <.badge kind={if employee.status == "active", do: :success, else: :neutral}>
                {employee.status}
              </.badge>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
