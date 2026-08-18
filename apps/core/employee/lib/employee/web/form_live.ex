defmodule Bilimbi.Core.Employee.Web.FormLive do
  @moduledoc """
  Employee create/edit form. Domain rules stay in `Bilimbi.Core.Employee`.

  Discovered routes do not set `live_action`, so new vs edit is taken from
  the presence of `:id` in the params.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Employee
  alias Ecto.Changeset

  @field_types %{
    employee_number: :string,
    full_name: :string,
    short_name: :string,
    designation: :string,
    employee_type: :string,
    email: :string,
    status: :string
  }

  @statuses ~w(pending probation active inactive terminated)

  @form_params [
    "employee_number",
    "full_name",
    "short_name",
    "designation",
    "employee_type",
    "email",
    "status"
  ]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    case Employee.list_employee_types(scope, company_id) do
      {:ok, types} ->
        {:ok,
         socket
         |> assign(:active_nav, "admin.employee")
         |> assign(:company_id, company_id)
         |> assign(:types, types)
         |> assign(:statuses, @statuses)}

      {:error, :company_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That company is not in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(%{"id" => _} = params, _uri, socket) do
    {:noreply, apply_action(assign(socket, :live_action, :edit), :edit, params)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(assign(socket, :live_action, :new), :new, params)}
  end

  defp apply_action(socket, _action, _params) when not is_map_key(socket.assigns, :company_id) do
    socket
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New employee")
    |> assign(:employee, nil)
    |> assign_form(form_changeset(%{"status" => "active", "employee_type" => "full_time"}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company_id

    with {employee_id, ""} <- Integer.parse(id),
         {:ok, employee} <- Employee.get_employee(scope, company_id, employee_id) do
      socket
      |> assign(:page_title, "Edit #{employee.full_name}")
      |> assign(:employee, employee)
      |> assign_form(form_changeset(form_values(employee)))
    else
      _ ->
        socket
        |> put_flash(:error, "That employee does not exist in this company.")
        |> push_navigate(to: ~p"/employees")
    end
  end

  @impl true
  def handle_event("validate", %{"employee" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params))}
  end

  def handle_event("save", %{"employee" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    scope = socket.assigns.current_scope.scope
    changeset = form_changeset(params)

    if changeset.valid? do
      attributes = Map.take(params, @form_params)

      case Employee.create_employee(scope, socket.assigns.company_id, attributes) do
        {:ok, employee} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{employee.full_name} was created.")
           |> push_navigate(to: ~p"/employees/#{employee.id}")}

        {:error, :company_not_found} ->
          {:noreply, put_flash(socket, :error, "That company is not in this workspace.")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    scope = socket.assigns.current_scope.scope
    employee = socket.assigns.employee
    changeset = form_changeset(params)

    if changeset.valid? do
      attributes = Map.take(params, @form_params)

      case Employee.update_employee(scope, socket.assigns.company_id, employee.id, attributes) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{updated.full_name} was updated.")
           |> push_navigate(to: ~p"/employees/#{updated.id}")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}

        {:error, :invariant_violation} ->
          {:noreply,
           put_flash(socket, :error, "The platform orchestrator identity cannot be changed.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "That employee could not be updated.")}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp form_values(employee) do
    %{
      "employee_number" => employee.employee_number,
      "full_name" => employee.full_name,
      "short_name" => employee.short_name,
      "designation" => employee.designation,
      "employee_type" => employee.employee_type,
      "email" => employee.email,
      "status" => employee.status
    }
  end

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:employee_number, :full_name, :employee_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> Map.put(:action, :validate)
  end

  defp copy_domain_errors(form_changeset, %Changeset{} = domain_changeset) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field) do
        add_error(acc, field, message, opts)
      else
        acc
      end
    end)
    |> Map.put(:action, :insert)
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :employee))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:form}>
        <p class="mb-2 text-xs">
          <.link navigate={~p"/employees"} class="font-medium text-ink-muted hover:text-ink">
            ← Employees
          </.link>
        </p>

        <.header>
          {@page_title}
          <:subtitle>
            Employment records belong to {@current_scope.user["company_name"]}.
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="employee-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-5 flex flex-col gap-4 rounded-xl border border-line bg-surface px-6 py-5"
        >
          <.input
            field={@form[:employee_number]}
            id="employee-number"
            label="Employee number"
            autocomplete="off"
          />
          <.input
            field={@form[:full_name]}
            id="employee-full-name"
            label="Full name"
            autocomplete="off"
          />
          <.input
            field={@form[:short_name]}
            id="employee-short-name"
            label="Short name"
            autocomplete="off"
          />
          <.input
            field={@form[:designation]}
            id="employee-designation"
            label="Designation"
            autocomplete="off"
          />
          <.input
            field={@form[:employee_type]}
            id="employee-type"
            type="select"
            label="Type"
            options={for type <- @types, do: {type.label, type.code}}
          />
          <.input
            field={@form[:email]}
            id="employee-email"
            type="email"
            label="Email"
            autocomplete="off"
          />
          <.input
            field={@form[:status]}
            id="employee-status"
            type="select"
            label="Status"
            options={for status <- @statuses, do: {status, status}}
          />
          <div class="mt-2 flex items-center gap-3">
            <.button id="employee-save" variant="primary" type="submit" phx-disable-with="Saving…">
              Save employee
            </.button>

            <.link
              navigate={~p"/employees"}
              class="text-sm font-medium text-ink-muted hover:text-ink"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </.page>
    </Layouts.app>
    """
  end
end
