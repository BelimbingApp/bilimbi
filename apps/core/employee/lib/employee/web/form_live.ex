defmodule Bilimbi.Core.Employee.Web.FormLive do
  @moduledoc """
  Employee create/edit form with full Belimbing parity. Domain rules stay in `Bilimbi.Core.Employee`.

  Discovered routes do not set `live_action`, so new vs edit is taken from
  the presence of `:id` in the params.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.TypeSummary
  alias Ecto.Changeset

  @field_types %{
    company_id: :integer,
    department_id: :integer,
    supervisor_id: :integer,
    employee_number: :string,
    full_name: :string,
    short_name: :string,
    designation: :string,
    employee_type: :string,
    email: :string,
    mobile_number: :string,
    status: :string,
    employment_start: :date,
    employment_end: :date,
    user_id: :integer
  }

  @statuses ~w(active pending probation inactive terminated)

  @system_type_fallbacks [
    %TypeSummary{id: nil, code: "full_time", label: "Full Time", is_system: true},
    %TypeSummary{id: nil, code: "part_time", label: "Part Time", is_system: true},
    %TypeSummary{id: nil, code: "contractor", label: "Contractor", is_system: true},
    %TypeSummary{id: nil, code: "intern", label: "Intern", is_system: true},
    %TypeSummary{id: nil, code: "agent", label: "Agent", is_system: true}
  ]

  @form_params [
    "company_id",
    "department_id",
    "supervisor_id",
    "employee_number",
    "full_name",
    "short_name",
    "designation",
    "employee_type",
    "email",
    "mobile_number",
    "status",
    "employment_start",
    "employment_end"
  ]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    user_company_id = socket.assigns.current_scope.user["company_id"]

    {:ok, companies} = Company.list_companies(scope)

    active_company_id =
      case Enum.find(companies, &(&1.id == user_company_id)) do
        nil -> (List.first(companies) && List.first(companies).id) || user_company_id
        found -> found.id
      end

    {:ok,
     socket
     |> assign(:active_nav, "admin.employee")
     |> assign(:companies, companies)
     |> assign(:company_id, active_company_id)
     |> assign(:statuses, @statuses)}
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
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company_id

    socket
    |> assign(:page_title, "Add Employee")
    |> assign(:page_subtitle, "Create a new employment record")
    |> assign(:save_button_label, "Add Employee")
    |> assign(:employee, nil)
    |> load_company_context(scope, company_id, nil)
    |> assign_form(
      form_changeset(%{
        "company_id" => company_id,
        "status" => "active",
        "employee_type" => "full_time"
      })
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope.scope

    with {employee_id, ""} <- Integer.parse(id),
         {:ok, employee} <- Employee.get_employee(scope, employee_id) do
      company_id = employee.company_id
      linked_user_id = find_linked_user_id(scope, employee.id)

      socket
      |> assign(:page_title, "Edit Employee")
      |> assign(:page_subtitle, "Update employment record")
      |> assign(:save_button_label, "Save Employee")
      |> assign(:employee, employee)
      |> assign(:company_id, company_id)
      |> load_company_context(scope, company_id, employee.id)
      |> assign_form(form_changeset(form_values(employee, linked_user_id)))
    else
      _ ->
        socket
        |> put_flash(:error, "That employee does not exist in this workspace.")
        |> push_navigate(to: ~p"/employees")
    end
  end

  @impl true
  def handle_event("validate", %{"employee" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    current_company_id = socket.assigns.company_id
    new_company_id = parse_id(params["company_id"]) || current_company_id

    current_employee_id = if socket.assigns.employee, do: socket.assigns.employee.id, else: nil

    socket =
      if new_company_id != current_company_id do
        socket
        |> assign(:company_id, new_company_id)
        |> load_company_context(scope, new_company_id, current_employee_id)
      else
        socket
      end

    {:noreply, assign_form(socket, form_changeset(params))}
  end

  def handle_event("save", %{"employee" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    scope = socket.assigns.current_scope.scope
    changeset = form_changeset(params)

    if changeset.valid? do
      company_id = parse_id(params["company_id"]) || socket.assigns.company_id
      user_id = parse_id(params["user_id"])
      attributes = extract_attributes(params, company_id)

      case Employee.create_employee(scope, company_id, attributes) do
        {:ok, employee} ->
          _ = sync_user_link(scope, company_id, employee.id, user_id)

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
      company_id = parse_id(params["company_id"]) || employee.company_id
      user_id = parse_id(params["user_id"])
      attributes = extract_attributes(params, company_id)

      case Employee.update_employee(scope, company_id, employee.id, attributes) do
        {:ok, updated} ->
          _ = sync_user_link(scope, company_id, updated.id, user_id)

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

  defp load_company_context(socket, scope, company_id, current_employee_id) do
    departments =
      case Company.list_departments(scope, company_id) do
        {:ok, depts} -> depts
        _ -> []
      end

    supervisors =
      case Employee.list_employees(scope, company_id) do
        {:ok, emps} ->
          if current_employee_id do
            Enum.filter(emps, &(&1.id != current_employee_id))
          else
            emps
          end

        _ ->
          []
      end

    types =
      case Employee.list_employee_types(scope, company_id) do
        {:ok, []} -> @system_type_fallbacks
        {:ok, t_list} -> t_list
        _ -> @system_type_fallbacks
      end

    available_users = list_assignable_users(scope, company_id, current_employee_id)

    socket
    |> assign(:departments, departments)
    |> assign(:supervisors, supervisors)
    |> assign(:types, types)
    |> assign(:available_users, available_users)
  end

  defp list_assignable_users(scope, company_id, current_employee_id) do
    user_mod = Module.concat(["Bilimbi", "Core", "User"])

    if Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :list_users, 1) do
      case apply(user_mod, :list_users, [scope]) do
        {:ok, users} ->
          Enum.filter(users, fn u ->
            (u.company_id == company_id or is_nil(u.company_id)) and
              (is_nil(u.employee_id) or
                 (current_employee_id && u.employee_id == current_employee_id))
          end)

        _ ->
          []
      end
    else
      []
    end
  end

  defp find_linked_user_id(scope, employee_id) do
    user_mod = Module.concat(["Bilimbi", "Core", "User"])

    if Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :list_users, 1) do
      case apply(user_mod, :list_users, [scope]) do
        {:ok, users} ->
          case Enum.find(users, &(&1.employee_id == employee_id)) do
            nil -> nil
            user -> user.id
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp sync_user_link(scope, company_id, employee_id, new_user_id) do
    user_mod = Module.concat(["Bilimbi", "Core", "User"])

    if Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :list_users, 1) and
         function_exported?(user_mod, :update_user, 4) do
      case apply(user_mod, :list_users, [scope]) do
        {:ok, users} ->
          currently_linked = Enum.find(users, &(&1.employee_id == employee_id))
          current_linked_user_id = if currently_linked, do: currently_linked.id, else: nil

          cond do
            new_user_id == current_linked_user_id ->
              :ok

            is_nil(new_user_id) and not is_nil(currently_linked) ->
              apply(user_mod, :update_user, [
                scope,
                currently_linked.company_id || company_id,
                currently_linked.id,
                %{employee_id: nil}
              ])

            not is_nil(new_user_id) ->
              if currently_linked && currently_linked.id != new_user_id do
                apply(user_mod, :update_user, [
                  scope,
                  currently_linked.company_id || company_id,
                  currently_linked.id,
                  %{employee_id: nil}
                ])
              end

              target_user = Enum.find(users, &(&1.id == new_user_id))
              target_company_id = (target_user && target_user.company_id) || company_id

              apply(user_mod, :update_user, [
                scope,
                target_company_id,
                new_user_id,
                %{employee_id: employee_id}
              ])

            true ->
              :ok
          end

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp extract_attributes(params, company_id) do
    params
    |> Map.take(@form_params)
    |> Map.put("company_id", company_id)
    |> Enum.into(%{}, fn {k, v} ->
      v_clean = if is_binary(v), do: String.trim(v), else: v
      v_final = if v_clean == "", do: nil, else: v_clean
      {k, v_final}
    end)
  end

  defp parse_id(val) when is_integer(val), do: val

  defp parse_id(val) when is_binary(val) do
    case Integer.parse(val) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp form_values(employee, linked_user_id) do
    %{
      "company_id" => employee.company_id,
      "department_id" => employee.department_id,
      "supervisor_id" => employee.supervisor_id,
      "employee_number" => employee.employee_number,
      "full_name" => employee.full_name,
      "short_name" => employee.short_name,
      "designation" => employee.designation,
      "employee_type" => employee.employee_type,
      "email" => employee.email,
      "mobile_number" => employee.mobile_number,
      "status" => employee.status,
      "employment_start" =>
        employee.employment_start && Date.to_iso8601(employee.employment_start),
      "employment_end" => employee.employment_end && Date.to_iso8601(employee.employment_end),
      "user_id" => linked_user_id
    }
  end

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:company_id, :employee_number, :full_name, :employee_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_employment_period()
    |> Map.put(:action, :validate)
  end

  defp validate_employment_period(changeset) do
    start_date = get_field(changeset, :employment_start)
    end_date = get_field(changeset, :employment_end)

    if start_date && end_date && Date.before?(end_date, start_date) do
      add_error(changeset, :employment_end, "must be on or after employment start")
    else
      changeset
    end
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

  defp department_name(%{type: %{name: name}}) when is_binary(name) and name != "", do: name
  defp department_name(%{id: id}), do: "Department #{id}"
  defp department_name(_), do: "Department"

  defp status_label("active"), do: "Active"
  defp status_label("pending"), do: "Pending"
  defp status_label("probation"), do: "Probation"
  defp status_label("inactive"), do: "Inactive"
  defp status_label("terminated"), do: "Terminated"
  defp status_label(status), do: Phoenix.Naming.humanize(status)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:list}>
        <.header>
          <div class="flex items-center gap-2">
            <span>{@page_title}</span>
            <.icon name="hero-star" class="h-5 w-5 text-ink-muted/50" />
          </div>
          <:subtitle>
            {@page_subtitle}
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/employees"}
              class="inline-flex items-center gap-1 text-sm font-medium text-action-base hover:text-action transition-colors"
            >
              ← Back
            </.link>
          </:actions>
        </.header>

        <.form
          for={@form}
          id="employee-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-3 rounded-xl border border-line bg-surface p-6 shadow-xs"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-2">
            <div>
              <.input
                field={@form[:company_id]}
                id="employee-company-id"
                type="select"
                label="COMPANY"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                prompt="Select company..."
                options={for company <- @companies, do: {company.name, company.id}}
                required
              />
            </div>
            <div>
              <.input
                field={@form[:department_id]}
                id="employee-department-id"
                type="select"
                label="DEPARTMENT"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                prompt="None"
                options={for dept <- @departments, do: {department_name(dept), dept.id}}
              />
            </div>

            <div>
              <.input
                field={@form[:employee_number]}
                id="employee-number"
                label="EMPLOYEE NUMBER *"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Employee ID or number"
                autocomplete="off"
                required
              />
            </div>
            <div>
              <.input
                field={@form[:full_name]}
                id="employee-full-name"
                label="FULL NAME *"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Full legal name"
                autocomplete="off"
                required
              />
            </div>

            <div>
              <.input
                field={@form[:short_name]}
                id="employee-short-name"
                label="SHORT NAME"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Preferred or display name"
                autocomplete="off"
              />
            </div>
            <div>
              <.input
                field={@form[:designation]}
                id="employee-designation"
                label="DESIGNATION"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Job title or designation"
                autocomplete="off"
              />
            </div>

            <div>
              <.input
                field={@form[:employee_type]}
                id="employee-type"
                type="select"
                label="EMPLOYEE TYPE"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                options={for type <- @types, do: {type.label, type.code}}
                required
              />
            </div>
            <div>
              <.input
                field={@form[:status]}
                id="employee-status"
                type="select"
                label="STATUS"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                options={for status <- @statuses, do: {status_label(status), status}}
                required
              />
            </div>

            <div>
              <.input
                field={@form[:email]}
                id="employee-email"
                type="email"
                label="EMAIL"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Work email address"
                autocomplete="off"
              />
            </div>
            <div>
              <.input
                field={@form[:mobile_number]}
                id="employee-mobile-number"
                label="MOBILE NUMBER"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Contact number"
                autocomplete="off"
              />
            </div>

            <div>
              <.input
                field={@form[:employment_start]}
                id="employee-employment-start"
                type="date"
                label="EMPLOYMENT START"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
              />
            </div>
            <div>
              <.input
                field={@form[:employment_end]}
                id="employee-employment-end"
                type="date"
                label="EMPLOYMENT END"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
              />
            </div>

            <div>
              <.input
                field={@form[:supervisor_id]}
                id="employee-supervisor-id"
                type="select"
                label="SUPERVISOR"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                prompt="None"
                options={for sup <- @supervisors, do: {sup.full_name, sup.id}}
              />
            </div>
            <div>
              <.input
                field={@form[:user_id]}
                id="employee-user-id"
                type="select"
                label="USER ACCOUNT"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                prompt="None"
                options={for user <- @available_users, do: {user.name || user.email, user.id}}
              />
            </div>
          </div>

          <div class="mt-4 flex items-center gap-4">
            <.button id="employee-save" variant="primary" type="submit" phx-disable-with="Saving…">
              {@save_button_label}
            </.button>

            <.link
              navigate={~p"/employees"}
              class="text-sm font-medium text-ink-muted hover:text-ink transition-colors"
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
