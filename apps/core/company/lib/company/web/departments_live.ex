defmodule Bilimbi.Core.Company.Web.DepartmentsLive do
  @moduledoc """
  Administration for a company's departments.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Department

  @update_capability "admin.company.update"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    case Integer.parse(id) do
      {company_id, ""} ->
        case Company.get_company(scope, company_id) do
          {:ok, company} ->
            {:ok, departments} = Company.list_departments(scope, company_id)

            {:ok,
             socket
             |> assign(:page_title, "#{Company.Summary.display_name(company)} — Departments")
             |> assign(:active_nav, "admin.company")
             |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
             |> assign(:company, company)
             |> assign(:departments_count, length(departments))
             |> assign(:modal_action, nil)
             |> assign(:available_types, [])
             |> assign_form(nil)
             |> stream(:departments, departments)}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Company not found.")
             |> push_navigate(to: ~p"/companies")}
        end

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid company ID.")
         |> push_navigate(to: ~p"/companies")}
    end
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{can_update?: false}} = socket)
      when event in ["new", "save", "update_status", "delete"],
      do: write_forbidden(socket)

  def handle_event("new", _params, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Company.list_available_department_types(scope, company_id) do
      {:ok, available_types} ->
        changeset =
          Department.changeset(%Department{company_id: company_id}, %{status: "active"})

        {:noreply,
         socket
         |> assign(:modal_action, :new)
         |> assign(:available_types, available_types)
         |> assign_form(changeset)}

      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Company not found.")
         |> push_navigate(to: ~p"/companies")}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_action, nil)
     |> assign_form(nil)}
  end

  def handle_event("validate", %{"department" => params}, socket) do
    company_id = socket.assigns.company.id

    changeset =
      %Department{company_id: company_id}
      |> Department.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"department" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Company.create_department(scope, company_id, params) do
      {:ok, _department} ->
        {:ok, departments} = Company.list_departments(scope, company_id)

        {:noreply,
         socket
         |> put_flash(:info, "Department added successfully.")
         |> assign(:modal_action, nil)
         |> assign(:departments_count, length(departments))
         |> assign_form(nil)
         |> stream(:departments, departments, reset: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Company not found.")
         |> push_navigate(to: ~p"/companies")}
    end
  end

  def handle_event("update_status", %{"id" => id, "status" => status}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Integer.parse(id) do
      {dept_id, ""} ->
        case Company.update_department_status(scope, company_id, dept_id, status) do
          {:ok, updated_dept} ->
            {:noreply,
             socket
             |> put_flash(:info, "Department status updated to #{status}.")
             |> stream_insert(:departments, updated_dept)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not update status.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Integer.parse(id) do
      {dept_id, ""} ->
        case Company.delete_department(scope, company_id, dept_id) do
          :ok ->
            {:ok, departments} = Company.list_departments(scope, company_id)

            {:noreply,
             socket
             |> put_flash(:info, "Department removed.")
             |> assign(:departments_count, length(departments))
             |> stream(:departments, departments, reset: true)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not remove department.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp write_forbidden(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "You do not have permission to change company administration data."
     )}
  end

  defp assign_form(socket, nil), do: assign(socket, :form, nil)

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "department"))
  end

  defp type_options(available_types) do
    Enum.map(available_types, fn type ->
      {"#{type.name} (#{type.code})", type.id}
    end)
  end

  defp status_options do
    Enum.map(Department.statuses(), fn s -> {String.capitalize(s), s} end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:type_options, type_options(assigns.available_types))
      |> assign(:status_options, status_options())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          {Company.Summary.display_name(@company)} — Departments
          <:subtitle>
            <code class="text-xs font-medium">{@company.code}</code>
          </:subtitle>
          <:actions>
            <.button navigate={~p"/companies/#{@company.id}"} class="text-xs">
              Back to {Company.Summary.display_name(@company)}
            </.button>
            <.button
              :if={@can_update?}
              id="add-dept-btn"
              phx-click="new"
              variant="primary"
              class="text-xs"
            >
              Add Department
            </.button>
          </:actions>
        </.header>

        <.card id="company-departments-card" inner_class="p-0">
          <.table
            id="company-departments"
            rows={@streams.departments}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, dept} -> dept end}
            caption="Company Departments"
            framed={false}
          >
            <:col :let={dept} label="Code">
              <code class="text-xs font-medium">{dept.type.code}</code>
            </:col>
            <:col :let={dept} label="Department Name">
              <span class="font-medium text-ink-strong">{dept.type.name}</span>
            </:col>
            <:col :let={dept} label="Category">
              <.badge kind={:neutral}>
                {String.capitalize(dept.type.category)}
              </.badge>
            </:col>
            <:col :let={dept} label="Status">
              <.badge kind={
                case dept.status do
                  "active" -> :success
                  "suspended" -> :warning
                  _ -> :neutral
                end
              }>
                {dept.status}
              </.badge>
            </:col>
            <:action :let={dept}>
              <div class="flex items-center gap-2">
                <button
                  :if={@can_update? and dept.status != "active"}
                  type="button"
                  id={"activate-dept-#{dept.id}"}
                  phx-click="update_status"
                  phx-value-id={dept.id}
                  phx-value-status="active"
                  class="text-xs text-action hover:underline"
                >
                  Activate
                </button>
                <button
                  :if={@can_update? and dept.status != "suspended"}
                  type="button"
                  id={"suspend-dept-#{dept.id}"}
                  phx-click="update_status"
                  phx-value-id={dept.id}
                  phx-value-status="suspended"
                  class="text-xs text-warning hover:underline"
                >
                  Suspend
                </button>
                <button
                  :if={@can_update? and dept.status != "inactive"}
                  type="button"
                  id={"deactivate-dept-#{dept.id}"}
                  phx-click="update_status"
                  phx-value-id={dept.id}
                  phx-value-status="inactive"
                  class="text-xs text-ink-subtle hover:underline"
                >
                  Deactivate
                </button>
                <button
                  :if={@can_update?}
                  type="button"
                  id={"delete-dept-#{dept.id}"}
                  phx-click="delete"
                  phx-value-id={dept.id}
                  data-confirm="Are you sure you want to remove this department?"
                  class="text-xs text-danger hover:underline ml-2"
                >
                  Remove
                </button>
              </div>
            </:action>
            <:empty :if={@departments_count == 0}>
              No departments configured for this company yet.
            </:empty>
          </.table>
        </.card>

        <div
          :if={@modal_action == :new}
          id="department-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              Add Department
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              Select an available department type to establish in {Company.Summary.display_name(@company)}.
            </p>

            <.form
              :if={@form}
              for={@form}
              id="department-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-4 space-y-4"
            >
              <.input
                field={@form[:department_type_id]}
                id="department-type-id"
                type="select"
                label="Department Type"
                options={@type_options}
                prompt="Select a department type"
                required
              />
              <.input
                field={@form[:status]}
                id="department-status"
                type="select"
                label="Initial Status"
                options={@status_options}
                required
              />

              <div class="mt-6 flex justify-end gap-2">
                <.button type="button" phx-click="close_modal">
                  Cancel
                </.button>
                <.button
                  type="submit"
                  variant="primary"
                  disabled={@type_options == []}
                >
                  Add Department
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
