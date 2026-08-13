defmodule Bilimbi.Core.Employee.Web.TypeIndexLive do
  @moduledoc """
  Employee types available to the signed-in company.

  System types are company-less; custom types belong to the company.
  """

  use Bilimbi.Base.UI, :live_view

  import Bilimbi.Core.Employee.Web.Capabilities, only: [allowed?: 2]

  alias Bilimbi.Core.Employee

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    case Employee.list_employee_types(scope, company_id) do
      {:ok, types} ->
        {:ok,
         socket
         |> assign(:page_title, "Employee types")
         |> assign(:active_nav, :employees)
         |> stream(:employee_types, types)}

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
        <p class="mb-2 text-xs">
          <.link navigate={~p"/employees"} class="font-medium text-ink-muted hover:text-ink">
            ← Employees
          </.link>
        </p>
        
        <.header>
          Employee types
          <:subtitle>System types are company-less; custom types belong to this company.</:subtitle>
          
          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.employee-type.create")}
              id="employee-type-new"
              navigate={~p"/employee-types/new"}
              variant="primary"
            >
              New type
            </.button>
          </:actions>
        </.header>
        
        <div class="mt-5">
          <.table id="employee-types" rows={@streams.employee_types}>
            <:col :let={{_id, type}} label="Label">{type.label}</:col>
            
            <:col :let={{_id, type}} label="Code">
              <code class="text-xs font-medium">{type.code}</code>
            </:col>
            
            <:col :let={{_id, type}} label="Kind">
              <.badge kind={if type.is_system, do: :neutral, else: :success}>
                {if type.is_system, do: "system", else: "custom"}
              </.badge>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
