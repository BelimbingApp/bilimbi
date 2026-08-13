defmodule BilimbiWeb.EmployeeLive.Show do
  @moduledoc """
  One employee in the signed-in company, via `Bilimbi.Core.Employee.get_employee/3`.

  Deleting the platform orchestrator (`SYS-001` / `agent`) is refused by the
  domain as `:invariant_violation`; this screen reports that honestly rather
  than hiding the row.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Employee
  alias BilimbiWeb.UserAuth

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    with {employee_id, ""} <- Integer.parse(id),
         {:ok, employee} <- Employee.get_employee(scope, company_id, employee_id) do
      {:ok,
       socket
       |> assign(:page_title, employee.full_name)
       |> assign(:active_nav, :employees)
       |> assign(:employee, employee)}
    else
      _ -> {:ok, not_found(socket)}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    employee = socket.assigns.employee
    company_id = socket.assigns.current_scope.user["company_id"]

    cond do
      not UserAuth.allowed?(socket.assigns.current_scope, "admin.employee.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have access to that action.")}

      true ->
        case Employee.delete_employee(scope, company_id, employee.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "#{employee.full_name} was deleted.")
             |> push_navigate(to: ~p"/employees")}

          {:error, :invariant_violation} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "The platform orchestrator cannot be deleted."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "That employee could not be deleted.")}
        end
    end
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That employee does not exist in this company.")
    |> push_navigate(to: ~p"/employees")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <p class="mb-2 text-xs">
          <.link navigate={~p"/employees"} class="font-medium text-ink-muted hover:text-ink">
            ← Employees
          </.link>
        </p>

        <.header>
          {@employee.full_name}
          <:subtitle>
            <code class="text-ink-subtle">{@employee.employee_number}</code>
          </:subtitle>
          <:actions>
            <.badge kind={if @employee.status == "active", do: :success, else: :neutral}>
              {@employee.status}
            </.badge>
            <.link
              :if={UserAuth.allowed?(@current_scope, "admin.employee.update")}
              navigate={~p"/employees/#{@employee.id}/edit"}
              id="employee-edit"
              class="rounded-md px-2.5 py-1.5 text-xs font-medium text-ink-muted ring-1 ring-line transition hover:bg-surface-sunken hover:text-ink"
            >
              Edit
            </.link>
          </:actions>
        </.header>

        <div class="mt-5">
          <.list>
            <:item title="Short name">
              {display_or_dash(@employee.short_name)}
            </:item>
            <:item title="Designation">
              {display_or_dash(@employee.designation)}
            </:item>
            <:item title="Type">{@employee.employee_type}</:item>
            <:item title="Email">
              {display_or_dash(@employee.email)}
            </:item>
            <:item title="Employment start">
              {display_or_dash(@employee.employment_start)}
            </:item>
            <:item title="Employment end">
              {display_or_dash(@employee.employment_end)}
            </:item>
          </.list>
        </div>

        <div
          :if={UserAuth.allowed?(@current_scope, "admin.employee.delete")}
          id="employee-danger"
          class="mt-8 rounded-xl border border-line bg-surface px-5 py-4"
        >
          <div class="flex items-center justify-between gap-4">
            <div>
              <h2 class="text-sm font-semibold text-ink-strong">Delete this employee</h2>
              <p class="mt-0.5 text-xs text-ink-subtle">
                Removes the employment record. The platform orchestrator cannot be deleted.
              </p>
            </div>
            <.button
              id="employee-delete"
              phx-click="delete"
              data-confirm={"Delete #{@employee.full_name}? This cannot be undone."}
              class="bg-danger text-sm font-medium text-ink-inverse transition hover:opacity-90"
            >
              Delete employee
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp display_or_dash(nil) do
    assigns = %{}

    ~H"""
    <span class="text-ink-faint">—</span>
    """
  end

  defp display_or_dash(value) do
    value
  end
end
