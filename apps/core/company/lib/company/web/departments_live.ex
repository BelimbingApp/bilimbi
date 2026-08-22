defmodule Bilimbi.Core.Company.Web.DepartmentsLive do
  @moduledoc """
  Administration for a company's departments.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.PrincipalDirectory
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
            department_head_names = resolve_department_heads(scope, departments)

            {:ok,
             socket
             |> assign(:page_title, "#{Company.Summary.display_name(company)} — Departments")
             |> assign(:active_nav, "admin.company")
             |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
             |> assign(:company, company)
             |> assign(:departments_count, length(departments))
             |> assign(:department_head_names, department_head_names)
             |> assign(:modal_action, nil)
             |> assign(:available_types, [])
             |> assign(:head_options, [])
             |> assign_form(nil)
             |> assign_head_form(nil)
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
  def handle_event(event, params, socket)
      when event in ["new", "save", "update_status", "delete", "edit_head", "save_head"] do
    if can_update?(socket) do
      handle_write_event(event, params, socket)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_action, nil)
     |> assign(:head_options, [])
     |> assign_form(nil)
     |> assign_head_form(nil)}
  end

  def handle_event("validate", %{"department" => params}, socket) do
    company_id = socket.assigns.company.id

    changeset =
      %Department{company_id: company_id}
      |> Department.changeset(creation_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp handle_write_event("new", _params, socket) do
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

  defp handle_write_event("save", %{"department" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Company.create_department(scope, company_id, creation_params(params)) do
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

  defp handle_write_event("update_status", %{"id" => id, "status" => status}, socket) do
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

  defp handle_write_event("delete", %{"id" => id}, socket) do
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

  defp handle_write_event("edit_head", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    with {:ok, department_id} <- parse_positive_id(id),
         {:ok, departments} <- Company.list_departments(scope, company_id),
         %Department{} = department <- Enum.find(departments, &(&1.id == department_id)),
         {:ok, head_options} <- head_choices(scope, company_id) do
      {:noreply,
       socket
       |> assign(:modal_action, :edit_head)
       |> assign(:editing_department_id, department.id)
       |> assign(:head_options, head_options)
       |> assign_head_form(department)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Department not found.")}

      :error ->
        {:noreply, put_flash(socket, :error, "Department not found.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not load eligible employees.")}
    end
  end

  defp handle_write_event("save_head", %{"department_head" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id
    department_id = Map.get(socket.assigns, :editing_department_id)

    case {department_id, parse_optional_positive_id(Map.get(params, "head_id"))} do
      {nil, _head_id} ->
        {:noreply, put_flash(socket, :error, "Choose a department before setting its head.")}

      {_department_id, {:ok, nil}} ->
        persist_department_head(socket, scope, company_id, department_id, nil)

      {_department_id, {:ok, head_id}} ->
        case head_choices(scope, company_id) do
          {:ok, head_options} ->
            case Enum.find(head_options, &(&1.id == head_id)) do
              nil ->
                {:noreply,
                 put_flash(
                   socket,
                   :error,
                   "That employee is not eligible to lead this department."
                 )}

              head ->
                persist_department_head(socket, scope, company_id, department_id, head)
            end

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not load eligible employees.")}
        end

      {_department_id, :error} ->
        {:noreply, put_flash(socket, :error, "Choose an eligible employee or clear the head.")}
    end
  end

  defp handle_write_event("save_head", _params, socket) do
    {:noreply, put_flash(socket, :error, "Choose an eligible employee or clear the head.")}
  end

  defp handle_write_event("edit_head", _params, socket) do
    {:noreply, put_flash(socket, :error, "Department not found.")}
  end

  defp persist_department_head(socket, scope, company_id, department_id, head) do
    head_id = if is_nil(head), do: nil, else: head.id

    case Company.update_department_head(scope, company_id, department_id, head_id) do
      {:ok, department} ->
        head_names =
          case head do
            nil -> socket.assigns.department_head_names
            %{id: id, name: name} -> Map.put(socket.assigns.department_head_names, id, name)
          end

        {:noreply,
         socket
         |> put_flash(
           :info,
           if(is_nil(head), do: "Department head cleared.", else: "Department head updated.")
         )
         |> assign(:department_head_names, head_names)
         |> assign(:modal_action, nil)
         |> assign(:head_options, [])
         |> assign_head_form(nil)
         |> stream_insert(:departments, department)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Department not found.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update department head.")}
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

  defp can_update?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @update_capability).allowed
  end

  defp assign_form(socket, nil), do: assign(socket, :form, nil)

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "department"))
  end

  defp assign_head_form(socket, nil), do: assign(socket, :head_form, nil)

  defp assign_head_form(socket, %Department{} = department) do
    head_id = if is_nil(department.head_id), do: "", else: to_string(department.head_id)

    assign(socket, :head_form, to_form(%{"head_id" => head_id}, as: "department_head"))
  end

  defp head_choices(scope, company_id) do
    PrincipalDirectory.choices(scope, :employee, %{company_id: company_id})
  end

  # Department heads are appointed only through `save_head`, which validates
  # the company-scoped employee choice immediately before the Company write.
  # The creation form has no head field, so ignore a forged one here.
  defp creation_params(params), do: Map.delete(params, "head_id")

  defp resolve_department_heads(scope, departments) do
    candidates =
      departments
      |> Enum.map(& &1.head_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{:employee, &1})

    with [_ | _] <- candidates,
         {:ok, named} <- PrincipalDirectory.rank(scope, candidates) do
      Map.new(named, fn %{id: id, name: name} -> {id, name} end)
    else
      _ -> %{}
    end
  end

  defp parse_positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_positive_id(_value), do: :error

  defp parse_optional_positive_id(value) when value in [nil, ""], do: {:ok, nil}
  defp parse_optional_positive_id(value), do: parse_positive_id(value)

  defp head_options(choices), do: Enum.map(choices, &{&1.name, &1.id})

  defp head_name(%Department{head_id: nil}, _names), do: "—"
  defp head_name(%Department{head_id: id}, names), do: Map.get(names, id, "—")

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
      |> assign(:head_options, head_options(assigns.head_options))
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
            <:col :let={dept} label="Head">
              {head_name(dept, @department_head_names)}
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
                  :if={@can_update?}
                  type="button"
                  id={"edit-dept-head-#{dept.id}"}
                  phx-click="edit_head"
                  phx-value-id={dept.id}
                  class="text-xs text-action hover:underline"
                >
                  Set Head
                </button>
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

        <div
          :if={@modal_action == :edit_head}
          id="department-head-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              Set Department Head
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              Choose the employee responsible for this department, or clear the current head.
            </p>

            <.form
              :if={@head_form}
              for={@head_form}
              id="department-head-form"
              phx-submit="save_head"
              class="mt-4 space-y-4"
            >
              <.input
                field={@head_form[:head_id]}
                id="department-head-id"
                type="select"
                label="Department Head"
                options={@head_options}
                prompt="No department head"
              />

              <div class="mt-6 flex justify-end gap-2">
                <.button type="button" phx-click="close_modal">
                  Cancel
                </.button>
                <.button type="submit" variant="primary">
                  Save Head
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
