defmodule Bilimbi.Core.Employee.Web.TypeIndexLive do
  @moduledoc """
  Employee types available to the signed-in company.

  System types are company-less; custom types belong to the company.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Employee

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    case Employee.list_employee_types(scope, company_id) do
      {:ok, types} ->
        {:ok,
         socket
         |> assign(:page_title, "Employee Types")
         |> assign(:active_nav, "admin.employee-type")
         |> assign(:employee_types_count, length(types))
         |> stream(:employee_types, types)}

      {:error, :company_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That company is not in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    if allowed?(socket.assigns.current_scope, "admin.employee-type.delete") do
      with {type_id, ""} <- Integer.parse(id_str),
           :ok <- Employee.delete_employee_type(scope, company_id, type_id) do
        {:ok, types} = Employee.list_employee_types(scope, company_id)

        {:noreply,
         socket
         |> put_flash(:info, "Employee type deleted.")
         |> assign(:employee_types_count, length(types))
         |> stream(:employee_types, types, reset: true)}
      else
        {:error, :in_use} ->
          {:noreply, put_flash(socket, :error, "Cannot delete: employees are using this type.")}

        {:error, :is_system} ->
          {:noreply, put_flash(socket, :error, "System employee types cannot be deleted.")}

        {:error, :type_not_found} ->
          {:noreply,
           put_flash(socket, :error, "That employee type does not exist in this company.")}

        {:error, :company_not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "That company is not in this workspace.")
           |> push_navigate(to: ~p"/dashboard")}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not delete employee type.")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "You do not have permission to delete employee types.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="employee-types-index">
        <p class="mb-2 text-xs">
          <.link navigate={~p"/employees"} class="font-medium text-ink-muted hover:text-ink">
            ← Employees
          </.link>
        </p>

        <.header>
          Employee Types
          <:title_actions>
            <button
              type="button"
              id="employee-types-pin"
              data-nav-pin="nav-admin-employee-type"
              title="Pin Employee Types to sidebar"
              aria-label="Pin Employee Types to sidebar"
              aria-pressed="false"
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:subtitle>System types are company-less; custom types belong to this company.</:subtitle>

          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.employee-type.create")}
              id="employee-type-new"
              navigate={~p"/employee-types/new"}
              variant="primary"
            >
              New Type
            </.button>
          </:actions>
        </.header>

        <.card id="employee-types-card" inner_class="p-0">
          <.table
            id="employee-types"
            rows={@streams.employee_types}
            row_id={fn {id, _type} -> id end}
            row_item={fn {_id, type} -> type end}
            framed={false}
          >
            <:col :let={type} label="Label">{type.label}</:col>

            <:col :let={type} label="Code">
              <code class="text-xs font-medium">{type.code}</code>
            </:col>

            <:col :let={type} label="Kind">
              <.badge kind={if type.is_system, do: :neutral, else: :success}>
                {if type.is_system, do: "system", else: "custom"}
              </.badge>
            </:col>

            <:action :let={type}>
              <div :if={not type.is_system} class="flex items-center gap-2">
                <.link
                  :if={allowed?(@current_scope, "admin.employee-type.update")}
                  id={"employee-type-edit-#{type.id}"}
                  navigate={~p"/employee-types/#{type.id}/edit"}
                  class="text-xs font-medium text-action hover:underline"
                >
                  Edit
                </.link>
                <button
                  :if={allowed?(@current_scope, "admin.employee-type.delete")}
                  id={"employee-type-delete-#{type.id}"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={type.id}
                  data-confirm={"Are you sure you want to delete #{type.label}?"}
                  class="cursor-pointer text-xs font-medium text-danger hover:underline"
                >
                  Delete
                </button>
              </div>
            </:action>

            <:empty :if={@employee_types_count == 0}>
              No employee types found.
            </:empty>
          </.table>
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
