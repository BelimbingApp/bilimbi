defmodule BilimbiWeb.CompanyLive.Show do
  @moduledoc """
  One company: its record, its users, and its employees — each through the
  owning module's scoped public API.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    case Integer.parse(id) do
      {company_id, ""} -> load_company(socket, scope, company_id)
      _ -> {:ok, not_found(socket)}
    end
  end

  defp load_company(socket, scope, company_id) do
    case Company.get_company(scope, company_id) do
      {:ok, company} ->
        {:ok, users} = User.list_company_users(scope, company_id)
        {:ok, employees} = Employee.list_employees(scope, company_id)

        {:ok,
         socket
         |> assign(:page_title, Company.Summary.display_name(company))
         |> assign(:active_nav, "admin.company")
         |> assign(:company, company)
         |> assign(:company_users_count, length(users))
         |> assign(:company_employees_count, length(employees))
         |> stream(:company_users, users)
         |> stream(:company_employees, employees)}

      {:error, :not_found} ->
        {:ok, not_found(socket)}
    end
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That company does not exist in this workspace.")
    |> push_navigate(to: ~p"/companies")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          {Company.Summary.display_name(@company)}
          <:subtitle>
            <code class="text-xs font-medium">{@company.code}</code>
          </:subtitle>
          <:actions>
            <.badge kind={if @company.status == "active", do: :success, else: :warning}>
              {@company.status}
            </.badge>
            <.button id="company-back" navigate={~p"/companies"}>
              Back to companies
            </.button>
          </:actions>
        </.header>

        <section id="company-users" class="mt-6">
          <h2 class="mb-2 text-sm font-semibold text-ink-strong">Users</h2>
          <.table
            id="company-users-table"
            rows={@streams.company_users}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, user} -> user end}
            caption="Users"
          >
            <:col :let={user} label="Name"><span class="font-medium">{user.name}</span></:col>
            <:col :let={user} label="Email">{user.email}</:col>
            <:col :let={user} label="Email verified">
              <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
                {if user.email_verified_at, do: "verified", else: "unverified"}
              </.badge>
            </:col>
            <:empty :if={@company_users_count == 0}>
              No users found for this company.
            </:empty>
          </.table>
        </section>

        <section id="company-employees" class="mt-6">
          <h2 class="mb-2 text-sm font-semibold text-ink-strong">Employees</h2>
          <.table
            id="company-employees-table"
            rows={@streams.company_employees}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, employee} -> employee end}
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
            <:empty :if={@company_employees_count == 0}>
              No employees found for this company.
            </:empty>
          </.table>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
