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
         |> assign(:active_nav, :companies)
         |> assign(:company, company)
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
        <p class="mb-2 text-xs">
          <.link
            navigate={~p"/companies"}
            class="font-medium text-ink-muted hover:text-ink"
          >
            ← Companies
          </.link>
        </p>

        <.header>
          {Company.Summary.display_name(@company)}
          <:subtitle>
            <code class="text-xs font-medium">{@company.code}</code>
          </:subtitle>
          <:actions>
            <.badge kind={if @company.status == "active", do: :success, else: :warning}>
              {@company.status}
            </.badge>
          </:actions>
        </.header>

        <section id="company-users" class="mt-6">
          <h2 class="mb-2 text-sm font-semibold text-ink-strong">Users</h2>
          <.table id="company-users-table" rows={@streams.company_users}>
            <:col :let={{_id, user}} label="Name"><span class="font-medium">{user.name}</span></:col>
            <:col :let={{_id, user}} label="Email">{user.email}</:col>
            <:col :let={{_id, user}} label="Email verified">
              <.badge kind={if user.email_verified_at, do: :success, else: :neutral}>
                {if user.email_verified_at, do: "verified", else: "unverified"}
              </.badge>
            </:col>
          </.table>
        </section>

        <section id="company-employees" class="mt-6">
          <h2 class="mb-2 text-sm font-semibold text-ink-strong">Employees</h2>
          <.table id="company-employees-table" rows={@streams.company_employees}>
            <:col :let={{_id, employee}} label="Name">
              <span class="font-medium">{employee.full_name}</span>
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
        </section>
      </div>
    </Layouts.app>
    """
  end
end
