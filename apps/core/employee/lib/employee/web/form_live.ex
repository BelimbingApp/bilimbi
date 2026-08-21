defmodule Bilimbi.Core.Employee.Web.FormLive do
  @moduledoc """
  Employee create/edit form with full Belimbing parity. Domain rules stay in `Bilimbi.Core.Employee`.

  Discovered routes do not set `live_action`, so new vs edit is taken from
  the presence of `:id` in the params.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.UI.DiscoveredPanels
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
    job_description: :string,
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
    "employment_end",
    "job_description"
  ]
  @create_capability "admin.employee.create"
  @update_capability "admin.employee.update"

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_scope.actor

    {:ok,
     socket
     |> assign(:active_nav, "admin.employee")
     |> assign(:companies, [])
     |> assign(:company_id, actor.company_id)
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
    actor = socket.assigns.current_scope.actor

    case Company.list_selectable_companies(actor, @create_capability) do
      {:ok, companies} ->
        company_id = actor.company_id

        socket
        |> assign(:page_title, "Add Employee")
        |> assign(:page_subtitle, "Create a new employment record")
        |> assign(:save_button_label, "Add Employee")
        |> assign(:employee, nil)
        |> assign(:companies, companies)
        |> assign(:company_id, company_id)
        |> load_company_context(scope, company_id, nil)
        |> assign_form(
          form_changeset(%{
            "company_id" => company_id,
            "status" => "active",
            "employee_type" => "full_time"
          })
        )

      {:error, :unauthorized} ->
        socket
        |> put_flash(:error, "You do not have permission to create employees.")
        |> push_navigate(to: ~p"/dashboard")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope.scope
    actor = socket.assigns.current_scope.actor

    with {employee_id, ""} <- Integer.parse(id),
         {:ok, employee} <- Employee.get_employee(scope, employee_id),
         {:ok, _company} <-
           Company.authorize_company_target(actor, employee.company_id, @update_capability),
         {:ok, companies} <- Company.list_selectable_companies(actor, @update_capability) do
      company_id = employee.company_id
      linked_user_id = find_linked_user_id(scope, company_id, employee.id)

      socket
      |> assign(:page_title, "Edit Employee")
      |> assign(:page_subtitle, "Update employment record")
      |> assign(:save_button_label, "Save Employee")
      |> assign(:employee, employee)
      |> assign(:companies, companies)
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

    params =
      if socket.assigns.live_action == :edit && socket.assigns.employee do
        Map.put_new(params, "company_id", socket.assigns.employee.company_id)
      else
        params
      end

    new_company_id =
      if socket.assigns.live_action == :edit do
        current_company_id
      else
        parse_id(params["company_id"]) || current_company_id
      end

    current_employee_id = if socket.assigns.employee, do: socket.assigns.employee.id, else: nil

    changeset = form_changeset(params)

    case authorize_company_target(socket, new_company_id, action_capability(socket)) do
      :ok ->
        socket =
          if new_company_id != current_company_id do
            socket
            |> assign(:company_id, new_company_id)
            |> load_company_context(scope, new_company_id, current_employee_id)
          else
            socket
          end

        {:noreply, assign_form(socket, changeset)}

      {:error, _reason} ->
        {:noreply, assign_form(socket, add_error(changeset, :company_id, "is not available"))}
    end
  end

  def handle_event("save", %{"employee" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    scope = socket.assigns.current_scope.scope
    params = drop_user_for_agent(params)
    changeset = form_changeset(params)

    if changeset.valid? do
      company_id = parse_id(params["company_id"]) || socket.assigns.company_id
      user_id = parse_id(params["user_id"])
      attributes = extract_attributes(params, company_id)

      case authorize_company_target(socket, company_id, @create_capability) do
        :ok ->
          create_employee(socket, scope, company_id, user_id, attributes, changeset)

        {:error, _reason} ->
          {:noreply, assign_form(socket, add_error(changeset, :company_id, "is not available"))}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    scope = socket.assigns.current_scope.scope
    employee = socket.assigns.employee

    params =
      params
      |> Map.put("company_id", employee.company_id)
      |> drop_user_for_agent()

    changeset = form_changeset(params)

    if changeset.valid? do
      company_id = employee.company_id
      user_id = parse_id(params["user_id"])
      attributes = extract_attributes(params, company_id)

      case authorize_company_target(socket, company_id, @update_capability) do
        :ok ->
          update_employee(socket, scope, employee, company_id, user_id, attributes, changeset)

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "That company is not available in this workspace.")
           |> push_navigate(to: ~p"/employees")}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp create_employee(socket, scope, company_id, user_id, attributes, changeset) do
    case Employee.create_employee(scope, company_id, attributes) do
      {:ok, employee} ->
        link_result = sync_user_link(scope, company_id, employee.id, user_id)

        {:noreply,
         socket
         |> put_flash(:info, "#{employee.full_name} was created.")
         |> flash_rejected_link(link_result)
         |> push_navigate(to: ~p"/employees/#{employee.id}")}

      {:error, :company_not_found} ->
        {:noreply, put_flash(socket, :error, "That company is not in this workspace.")}

      {:error, %Changeset{} = domain_changeset} ->
        {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}
    end
  end

  defp update_employee(socket, scope, employee, company_id, user_id, attributes, changeset) do
    case Employee.update_employee(scope, company_id, employee.id, attributes) do
      {:ok, updated} ->
        link_result = sync_user_link(scope, company_id, updated.id, user_id)

        {:noreply,
         socket
         |> put_flash(:info, "#{updated.full_name} was updated.")
         |> flash_rejected_link(link_result)
         |> push_navigate(to: ~p"/employees/#{updated.id}")}

      {:error, %Changeset{} = domain_changeset} ->
        {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}

      {:error, :invariant_violation} ->
        {:noreply,
         put_flash(socket, :error, "The platform orchestrator identity cannot be changed.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That employee could not be updated.")}
    end
  end

  defp authorize_company_target(socket, company_id, capability) do
    actor = socket.assigns.current_scope.actor

    case Company.authorize_company_target(actor, company_id, capability) do
      {:ok, _company} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp action_capability(%{assigns: %{live_action: :edit}}), do: @update_capability
  defp action_capability(_socket), do: @create_capability

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
    case employee_account_options(scope, company_id, current_employee_id) do
      {:ok, %{available_users: users}} -> users
      _error -> []
    end
  end

  defp find_linked_user_id(scope, company_id, employee_id) do
    case employee_account_options(scope, company_id, employee_id) do
      {:ok, %{linked_user_id: linked_user_id}} -> linked_user_id
      _error -> nil
    end
  end

  defp sync_user_link(scope, company_id, employee_id, new_user_id) do
    case DiscoveredPanels.dispatch("employee.accounts", :replace_employee_account, [
           scope,
           company_id,
           employee_id,
           new_user_id
         ]) do
      {:ok, _linked_user} ->
        :ok

      {:error, :not_installed} when is_nil(new_user_id) ->
        :ok

      {:error, _reason} ->
        {:error, :invalid_user}
    end
  end

  defp employee_account_options(scope, company_id, current_employee_id) do
    DiscoveredPanels.dispatch("employee.accounts", :employee_account_options, [
      scope,
      company_id,
      current_employee_id
    ])
  end

  # A refused link used to be discarded, so an operator whose chosen account was
  # taken between render and submit saw an unqualified success. The employee is
  # still saved -- only the link is refused -- so this reports rather than fails.
  defp flash_rejected_link(socket, {:error, :invalid_user}) do
    put_flash(
      socket,
      :error,
      "That user account is no longer available to link, so the employee was saved without it."
    )
  end

  defp flash_rejected_link(socket, _result), do: socket

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
      "job_description" => employee.job_description,
      "user_id" => linked_user_id
    }
  end

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:company_id, :employee_number, :full_name, :employee_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_supervisor_for_agent()
    |> validate_employment_period()
    |> Map.put(:action, :validate)
  end

  # Belimbing renders Job Description only for agent employees
  # (`create.blade.php:135`), where it holds a short role label rather than a
  # human's duties. The form re-renders on `phx-change`, so reading the current
  # selection off the form is enough to follow the type select.
  defp agent_type?(form),
    do: to_string(Phoenix.HTML.Form.input_value(form, :employee_type)) == "agent"

  # Belimbing makes the supervisor mandatory for agent employees and optional
  # for everyone else (`Create.php:121`). An agent acts on someone's behalf, so
  # the record has to say whose.
  defp validate_supervisor_for_agent(changeset) do
    if get_field(changeset, :employee_type) == "agent" do
      validate_required(changeset, [:supervisor_id])
    else
      changeset
    end
  end

  # Belimbing clears the account before writing when the type is agent
  # (`Create.php:57-59`). An agent employee is not a person with a login, and
  # the form leaves the select populated when the type is switched.
  defp drop_user_for_agent(%{"employee_type" => "agent"} = params),
    do: Map.put(params, "user_id", "")

  defp drop_user_for_agent(params), do: params

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
            <span>{@page_title}</span> <.icon name="hero-star" class="h-5 w-5 text-ink-muted/50" />
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
                disabled={@live_action == :edit}
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

            <div :if={agent_type?(@form)} class="md:col-span-2">
              <.input
                field={@form[:job_description]}
                id="employee-job-description"
                type="textarea"
                rows="3"
                label="JOB DESCRIPTION"
                label_class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                placeholder="Short role label, e.g. Customer support Agent"
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
