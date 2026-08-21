defmodule Bilimbi.Core.Employee.Web.ShowLive do
  @moduledoc """
  Shows one employee in the signed-in company and provides administrative management:
  in-place field editing, lifecycle status and type selection, department/supervisor
  assignments, and direct subordinates management with sortable table. Account
  linking and address attachments render as discovered embeds owned by Core User
  and Core Address (`employee.accounts`, `employee.addresses`); this page names
  neither module.

  Deleting the platform orchestrator (`SYS-001` / `agent`) is refused by the domain as
  `:invariant_violation`; this screen reports that honestly rather than hiding the row.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.DiscoveredPanels

  @manage_capability "admin.employee.update"

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee

  # `toggle_add_subordinate` only flips the add-subordinate form's
  # visibility assign; the persisting event is `add_subordinate`, which is
  # capability-guarded (#420).
  @write_guard_opt_out ~w(toggle_add_subordinate)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    with {employee_id, ""} <- Integer.parse(id),
         {:ok, employee} <- Employee.get_employee(scope, company_id, employee_id) do
      socket =
        socket
        |> assign(:page_title, Employee.Summary.display_name(employee))
        |> assign(:active_nav, "admin.employee")
        |> assign(:employee_id, employee_id)
        |> init_ui_state()
        |> load_data(employee)

      {:ok, socket}
    else
      _ -> {:ok, not_found(socket)}
    end
  end

  defp init_ui_state(socket) do
    socket
    |> assign(:adding_subordinate, false)
    |> assign(:selected_subordinate_id, "")
    |> assign(:subordinates_sort_by, "full_name")
    |> assign(:subordinates_sort_dir, "asc")
  end

  defp load_data(socket, employee) do
    scope = socket.assigns.current_scope.scope
    current_scope = socket.assigns.current_scope
    can_manage? = allowed?(current_scope, @manage_capability)
    can_delete? = allowed?(current_scope, "admin.employee.delete")
    company_id = employee.company_id

    # Company info
    company_name =
      case Company.get_company(scope, company_id) do
        {:ok, company} -> Company.Summary.display_name(company)
        _ -> "Company"
      end

    # Departments
    departments =
      case Company.list_departments(scope, company_id) do
        {:ok, depts} -> depts
        _ -> []
      end

    department_map =
      Map.new(departments, fn dept ->
        name = if dept.type, do: dept.type.name, else: "Department #{dept.id}"
        {dept.id, name}
      end)

    # Supervisors (eligible company employees excluding self)
    all_employees =
      case Employee.list_employees(scope, company_id) do
        {:ok, emps} -> emps
        _ -> []
      end

    supervisors = Enum.reject(all_employees, &(&1.id == employee.id))
    supervisor_map = Map.new(all_employees, &{&1.id, &1.full_name})

    # Employee Types
    employee_types =
      case Employee.list_employee_types(scope, company_id) do
        {:ok, types} -> types
        _ -> []
      end

    # Subordinates
    subordinates =
      case Employee.list_subordinates(scope, company_id, employee.id) do
        {:ok, subs} -> subs
        _ -> []
      end

    available_subordinates =
      case Employee.list_available_subordinates(scope, company_id, employee.id) do
        {:ok, avail} -> avail
        _ -> []
      end

    sorted_subordinates =
      sort_subordinates(
        subordinates,
        socket.assigns.subordinates_sort_by,
        socket.assigns.subordinates_sort_dir,
        department_map
      )

    socket
    |> assign(:employee, employee)
    |> assign(:can_manage?, can_manage?)
    |> assign(:can_delete?, can_delete?)
    |> assign(:company_name, company_name)
    |> assign(:departments, departments)
    |> assign(:department_map, department_map)
    |> assign(:supervisors, supervisors)
    |> assign(:supervisor_map, supervisor_map)
    |> assign(:employee_types, employee_types)
    |> assign(:subordinates, subordinates)
    |> assign(:available_subordinates, available_subordinates)
    |> assign(:sorted_subordinates, sorted_subordinates)
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That employee does not exist in this company.")
    |> push_navigate(to: ~p"/employees")
  end

  # --- Event Handlers: Inline Editing of Text Fields ---

  @impl true
  def handle_event("save_field", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      {field, value} = extract_field_and_value(params)

      if field do
        case Employee.update_employee(scope, employee.company_id, employee.id, %{field => value}) do
          {:ok, updated_employee} ->
            field_label = humanize_field(field)

            {:noreply,
             socket
             |> put_flash(:info, "#{field_label} updated successfully.")
             |> load_data(updated_employee)}

          {:error, %Ecto.Changeset{} = changeset} ->
            error_msg = format_changeset_error(changeset, field)
            {:noreply, put_flash(socket, :error, error_msg)}

          {:error, :invariant_violation} ->
            {:noreply,
             put_flash(socket, :error, "Cannot modify protected platform orchestrator identity.")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to update #{humanize_field(field)}.")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("save_status", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      status = params["status"] || params["value"] || ""

      case Employee.update_employee(scope, employee.company_id, employee.id, %{status: status}) do
        {:ok, updated_employee} ->
          {:noreply,
           socket
           |> put_flash(:info, "Status updated.")
           |> load_data(updated_employee)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update status.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("save_employee_type", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      type = params["employee_type"] || params["value"] || ""

      # The manifest-declared account operation owns the cross-module account
      # transition. It is not probing: a missing provider fails honestly, and
      # Core User performs the unlink and Employee write in one transaction.
      case DiscoveredPanels.dispatch("employee.accounts", :change_employee_type, [
             scope,
             employee.company_id,
             employee.id,
             type
           ]) do
        {:ok, updated_employee} ->
          {:noreply,
           socket
           |> put_flash(:info, "Employee type updated.")
           |> load_data(updated_employee)}

        {:error, :invariant_violation} ->
          {:noreply,
           put_flash(socket, :error, "Cannot modify protected platform orchestrator identity.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update employee type.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("save_department", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      dept_id_val = params["department_id"] || params["value"] || ""

      dept_id =
        case Integer.parse(to_string(dept_id_val)) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      case Employee.update_employee(scope, employee.company_id, employee.id, %{
             department_id: dept_id
           }) do
        {:ok, updated_employee} ->
          {:noreply,
           socket
           |> put_flash(:info, "Department assignment saved.")
           |> load_data(updated_employee)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update department assignment.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("save_supervisor", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      sup_id_val = params["supervisor_id"] || params["value"] || ""

      sup_id =
        case Integer.parse(to_string(sup_id_val)) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      case Employee.update_employee(scope, employee.company_id, employee.id, %{
             supervisor_id: sup_id
           }) do
        {:ok, updated_employee} ->
          {:noreply,
           socket
           |> put_flash(:info, "Supervisor assignment saved.")
           |> load_data(updated_employee)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update supervisor assignment.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  # --- Event Handlers: Subordinates ---

  def handle_event("toggle_add_subordinate", _params, socket) do
    {:noreply, assign(socket, :adding_subordinate, not socket.assigns.adding_subordinate)}
  end

  def handle_event("select_subordinate", %{"subordinate_id" => sub_id}, socket) do
    {:noreply, assign(socket, :selected_subordinate_id, sub_id)}
  end

  def handle_event("add_subordinate", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      sub_id_val = params["subordinate_id"] || socket.assigns.selected_subordinate_id

      case Integer.parse(to_string(sub_id_val)) do
        {sub_id, ""} when sub_id > 0 ->
          case Employee.assign_subordinate(scope, employee.company_id, employee.id, sub_id) do
            {:ok, _sub} ->
              {:noreply,
               socket
               |> put_flash(:info, "Subordinate assigned.")
               |> assign(:adding_subordinate, false)
               |> assign(:selected_subordinate_id, "")
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to assign subordinate.")}
          end

        _ ->
          {:noreply,
           put_flash(socket, :error, "Please select an employee to assign as subordinate.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("remove_subordinate", %{"id" => sub_id_str}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      case Integer.parse(sub_id_str) do
        {sub_id, ""} ->
          case Employee.remove_subordinate(scope, employee.company_id, employee.id, sub_id) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, "Subordinate removed.")
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to remove subordinate.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("sort_subordinates", params, socket) do
    sort_col = params["sort_by"] || params["sort"] || "full_name"
    current_dir = socket.assigns.subordinates_sort_dir
    current_col = socket.assigns.subordinates_sort_by

    new_dir =
      if current_col == sort_col and current_dir == "asc" do
        "desc"
      else
        "asc"
      end

    sorted =
      sort_subordinates(
        socket.assigns.subordinates,
        sort_col,
        new_dir,
        socket.assigns.department_map
      )

    {:noreply,
     socket
     |> assign(:subordinates_sort_by, sort_col)
     |> assign(:subordinates_sort_dir, new_dir)
     |> assign(:sorted_subordinates, sorted)}
  end

  # --- Event Handlers: Danger Zone ---

  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    employee = socket.assigns.employee
    company_id = socket.assigns.current_scope.user["company_id"]

    if socket.assigns.can_delete? do
      case Employee.delete_employee(scope, company_id, employee.id) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "#{employee.full_name} was deleted.")
           |> push_navigate(to: ~p"/employees")}

        {:error, :invariant_violation} ->
          {:noreply, put_flash(socket, :error, "The platform orchestrator cannot be deleted.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "That employee could not be deleted.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to that action.")}
    end
  end

  # --- Private Extraction & Formatting Helpers ---

  defp extract_field_and_value(params) do
    fields =
      ~w(full_name short_name employee_number designation job_description email mobile_number)

    Enum.find_value(fields, {nil, nil}, fn f ->
      cond do
        Map.has_key?(params, f) -> {String.to_existing_atom(f), Map.get(params, f)}
        Map.get(params, "field") == f -> {String.to_existing_atom(f), Map.get(params, "value")}
        true -> nil
      end
    end)
  end

  defp humanize_field(:full_name), do: "Full name"
  defp humanize_field(:short_name), do: "Short name"
  defp humanize_field(:employee_number), do: "Employee number"
  defp humanize_field(:designation), do: "Designation"
  defp humanize_field(:job_description), do: "Job description"
  defp humanize_field(:email), do: "Email"
  defp humanize_field(:mobile_number), do: "Mobile number"
  defp humanize_field(f), do: to_string(f)

  defp format_changeset_error(changeset, field) do
    case changeset.errors[field] do
      {msg, _} -> "#{humanize_field(field)} #{msg}."
      _ -> "Failed to update #{humanize_field(field)}."
    end
  end

  # --- Sorting Helpers ---

  defp sort_subordinates(subordinates, sort_by, sort_dir, department_map) do
    mult = if sort_dir == "desc", do: -1, else: 1

    Enum.sort(subordinates, fn a, b ->
      case sort_by do
        "full_name" ->
          compare_strings(a.full_name, b.full_name, mult, a.id, b.id)

        "designation" ->
          compare_strings(a.designation || "", b.designation || "", mult, a.id, b.id)

        "status" ->
          compare_strings(a.status, b.status, mult, a.id, b.id)

        "department" ->
          dept_a = Map.get(department_map, a.department_id, "")
          dept_b = Map.get(department_map, b.department_id, "")
          compare_strings(dept_a, dept_b, mult, a.id, b.id)

        _ ->
          compare_strings(a.full_name, b.full_name, mult, a.id, b.id)
      end
    end)
  end

  defp compare_strings(a, b, mult, id_a, id_b) do
    case {a, b} do
      {x, y} when x == y ->
        id_a <= id_b

      {x, y} ->
        cmp = if String.downcase(x) < String.downcase(y), do: -1, else: 1
        cmp * mult < 0
    end
  end

  # --- Render Template ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          {Employee.Summary.display_name(@employee)}
          <:subtitle>
            {@employee.designation || @employee.job_description || @employee.employee_number}
          </:subtitle>

          <:actions>
            <.button id="employee-back" navigate={~p"/employees"}>
              Back to List
            </.button>

            <.button
              :if={@can_manage?}
              id="employee-edit"
              navigate={~p"/employees/#{@employee.id}/edit"}
              variant="primary"
            >
              Edit employee
            </.button>
          </:actions>
        </.header>

        <div class="mt-6 space-y-6">
          <!-- Card 1: Employee Details with In-place Editing -->
          <.card id="employee-details-card">
            <div class="p-5 sm:p-6 space-y-4">
              <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                Employee Details
              </h3>

              <dl class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Full Name
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <.inline_edit
                        id="employee-full-name"
                        name="full_name"
                        label="Full Name"
                        value={@employee.full_name}
                        id_value={@employee.id}
                        save_event="save_field"
                      />
                    <% else %>
                      <span>{@employee.full_name}</span>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Short Name
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <.inline_edit
                        id="employee-short-name"
                        name="short_name"
                        label="Short Name"
                        value={@employee.short_name || ""}
                        id_value={@employee.id}
                        save_event="save_field"
                      />
                    <% else %>
                      <span>{display_or_dash(@employee.short_name)}</span>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Employee Number
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <.inline_edit
                        id="employee-number"
                        name="employee_number"
                        label="Employee Number"
                        value={@employee.employee_number}
                        id_value={@employee.id}
                        save_event="save_field"
                        class="font-mono"
                      />
                    <% else %>
                      <code class="font-mono text-ink-subtle">{@employee.employee_number}</code>
                    <% end %>
                  </dd>
                </div>

                <%= if @employee.employee_type == "agent" do %>
                  <div>
                    <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                      Job Description
                    </dt>

                    <dd class="mt-0.5 text-sm text-ink">
                      <%= if @can_manage? do %>
                        <.inline_edit
                          id="employee-job-description"
                          name="job_description"
                          label="Job Description"
                          value={@employee.job_description || ""}
                          id_value={@employee.id}
                          save_event="save_field"
                        />
                      <% else %>
                        <span>{display_or_dash(@employee.job_description)}</span>
                      <% end %>
                    </dd>
                  </div>
                <% end %>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Designation
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <.inline_edit
                        id="employee-designation"
                        name="designation"
                        label="Designation"
                        value={@employee.designation || ""}
                        id_value={@employee.id}
                        save_event="save_field"
                      />
                    <% else %>
                      <span>{display_or_dash(@employee.designation)}</span>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Email
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <.inline_edit
                        id="employee-email"
                        name="email"
                        label="Email"
                        value={@employee.email || ""}
                        id_value={@employee.id}
                        save_event="save_field"
                      />
                    <% else %>
                      <span>{display_or_dash(@employee.email)}</span>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Mobile Number
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <.inline_edit
                        id="employee-mobile-number"
                        name="mobile_number"
                        label="Mobile Number"
                        value={@employee.mobile_number || ""}
                        id_value={@employee.id}
                        save_event="save_field"
                      />
                    <% else %>
                      <span>{display_or_dash(@employee.mobile_number)}</span>
                    <% end %>
                  </dd>
                </div>
              </dl>
            </div>
          </.card>
          <!-- Card 2: Employment Information -->
          <.card id="employment-info-card">
            <div class="p-5 sm:p-6 space-y-4">
              <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                Employment Information
              </h3>

              <dl class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Company
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink px-1 -mx-1 py-0.5">{@company_name}</dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Department
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <form
                        phx-change="save_department"
                        id="employee-department-form"
                        class="inline-block"
                      >
                        <select
                          id="employee-department"
                          name="department_id"
                          class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                        >
                          <option value="" selected={is_nil(@employee.department_id)}>None</option>

                          <%= for dept <- @departments do %>
                            <option value={dept.id} selected={@employee.department_id == dept.id}>
                              {if dept.type, do: dept.type.name, else: "Department #{dept.id}"}
                            </option>
                          <% end %>
                        </select>
                      </form>
                    <% else %>
                      <span>{Map.get(@department_map, @employee.department_id, "None")}</span>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Supervisor
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <form
                        phx-change="save_supervisor"
                        id="employee-supervisor-form"
                        class="inline-block"
                      >
                        <select
                          id="employee-supervisor"
                          name="supervisor_id"
                          class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                        >
                          <option value="" selected={is_nil(@employee.supervisor_id)}>None</option>

                          <%= for sup <- @supervisors do %>
                            <option value={sup.id} selected={@employee.supervisor_id == sup.id}>
                              {sup.full_name}
                            </option>
                          <% end %>
                        </select>
                      </form>
                    <% else %>
                      <span>{Map.get(@supervisor_map, @employee.supervisor_id, "None")}</span>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Employee Type
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <form
                        phx-change="save_employee_type"
                        id="employee-type-form"
                        class="inline-block"
                      >
                        <select
                          id="employee-type"
                          name="employee_type"
                          class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                        >
                          <optgroup label="Human">
                            <%= for type <- Enum.reject(@employee_types, &(&1.code == "agent")) do %>
                              <option
                                value={type.code}
                                selected={@employee.employee_type == type.code}
                              >
                                {type.label}
                              </option>
                            <% end %>
                          </optgroup>

                          <optgroup label="Agent">
                            <%= for type <- Enum.filter(@employee_types, &(&1.code == "agent")) do %>
                              <option
                                value={type.code}
                                selected={@employee.employee_type == type.code}
                              >
                                {type.label}
                              </option>
                            <% end %>
                          </optgroup>
                        </select>
                      </form>
                    <% else %>
                      <.badge kind={if @employee.employee_type == "agent", do: :info, else: :neutral}>
                        {@employee.employee_type}
                      </.badge>
                    <% end %>
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Status
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink">
                    <%= if @can_manage? do %>
                      <form phx-change="save_status" id="employee-status-form" class="inline-block">
                        <select
                          id="employee-status"
                          name="status"
                          class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                        >
                          <option value="pending" selected={@employee.status == "pending"}>
                            Pending
                          </option>

                          <option value="probation" selected={@employee.status == "probation"}>
                            Probation
                          </option>

                          <option value="active" selected={@employee.status == "active"}>
                            Active
                          </option>

                          <option value="inactive" selected={@employee.status == "inactive"}>
                            Inactive
                          </option>

                          <option value="terminated" selected={@employee.status == "terminated"}>
                            Terminated
                          </option>
                        </select>
                      </form>
                    <% else %>
                      <.badge kind={status_badge_kind(@employee.status)}>
                        {String.capitalize(@employee.status)}
                      </.badge>
                    <% end %>
                  </dd>
                </div>

                <.discovered_panel
                  key="employee.accounts"
                  id="account-panel"
                  current_scope={@current_scope}
                  opts={
                    %{
                      employee_id: @employee.id,
                      company_id: @employee.company_id,
                      employee_type: @employee.employee_type
                    }
                  }
                />

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Employment Start
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink px-1 -mx-1 py-0.5 tabular-nums">
                    {display_or_dash(@employee.employment_start)}
                  </dd>
                </div>

                <div>
                  <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                    Employment End
                  </dt>

                  <dd class="mt-0.5 text-sm text-ink px-1 -mx-1 py-0.5 tabular-nums">
                    {display_or_dash(@employee.employment_end)}
                  </dd>
                </div>
              </dl>
            </div>
          </.card>
          <!-- Card 3: Direct Subordinates -->
          <.card id="subordinates-card">
            <div class="p-5 sm:p-6 space-y-4">
              <div class="flex items-center justify-between">
                <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle flex items-center gap-1.5">
                  <span>Subordinates</span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink">
                    {length(@subordinates)}
                  </span>
                </h3>

                <%= if @can_manage? do %>
                  <div class="flex items-center gap-2">
                    <%= if @adding_subordinate do %>
                      <form
                        phx-submit="add_subordinate"
                        id="add-subordinate-form"
                        class="flex items-center gap-2"
                      >
                        <select
                          id="employee-subordinate-select"
                          name="subordinate_id"
                          class="min-w-48 rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                        >
                          <option value="">Select employee...</option>

                          <%= for avail <- @available_subordinates do %>
                            <option value={avail.id}>{avail.full_name}</option>
                          <% end %>
                        </select>

                        <.button
                          id="btn-assign-subordinate"
                          type="submit"
                          variant="primary"
                          class="text-xs px-2.5 py-1"
                        >
                          Assign
                        </.button>

                        <.button
                          id="btn-cancel-add-subordinate"
                          type="button"
                          phx-click="toggle_add_subordinate"
                          class="text-xs px-2.5 py-1"
                        >
                          Cancel
                        </.button>
                      </form>
                    <% else %>
                      <.button
                        id="btn-toggle-add-subordinate"
                        phx-click="toggle_add_subordinate"
                        variant="primary"
                        class="text-xs px-2.5 py-1"
                      >
                        <.icon name="bilimbi-plus" class="size-3.5" /> <span>Add</span>
                      </.button>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <div class="overflow-x-auto">
                <table id="subordinates-table" class="w-full text-left text-xs text-ink">
                  <thead>
                    <tr class="border-b border-line text-ink-subtle">
                      <th class="py-2 pr-4 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_subordinates"
                          phx-value-sort_by="full_name"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Name</span>
                          <%= if @subordinates_sort_by == "full_name" do %>
                            <span>{if @subordinates_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-4 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_subordinates"
                          phx-value-sort_by="designation"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Designation</span>
                          <%= if @subordinates_sort_by == "designation" do %>
                            <span>{if @subordinates_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-4 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_subordinates"
                          phx-value-sort_by="status"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Status</span>
                          <%= if @subordinates_sort_by == "status" do %>
                            <span>{if @subordinates_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-4 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_subordinates"
                          phx-value-sort_by="department"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Department</span>
                          <%= if @subordinates_sort_by == "department" do %>
                            <span>{if @subordinates_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th :if={@can_manage?} class="py-2 pl-4 text-right font-semibold">Actions</th>
                    </tr>
                  </thead>

                  <tbody class="divide-y divide-line">
                    <%= if @sorted_subordinates == [] do %>
                      <tr>
                        <td
                          colspan={if @can_manage?, do: 5, else: 4}
                          class="py-6 text-center text-ink-subtle"
                        >
                          No subordinates.
                        </td>
                      </tr>
                    <% else %>
                      <%= for sub <- @sorted_subordinates do %>
                        <tr
                          id={"subordinate-row-#{sub.id}"}
                          class="hover:bg-surface-sunken/40 transition"
                        >
                          <td class="py-2 pr-4 font-medium text-ink">
                            <.link
                              navigate={~p"/employees/#{sub.id}"}
                              class="text-brand-strong hover:underline"
                            >
                              {sub.full_name}
                            </.link>
                          </td>

                          <td class="py-2 px-4 text-ink-subtle">
                            {display_or_dash(sub.designation)}
                          </td>

                          <td class="py-2 px-4">
                            <.badge kind={status_badge_kind(sub.status)}>
                              {String.capitalize(sub.status)}
                            </.badge>
                          </td>

                          <td class="py-2 px-4 text-ink-subtle">
                            {Map.get(@department_map, sub.department_id, "—")}
                          </td>

                          <td :if={@can_manage?} class="py-2 pl-4 text-right">
                            <.button
                              id={"remove-subordinate-#{sub.id}"}
                              type="button"
                              phx-click="remove_subordinate"
                              phx-value-id={sub.id}
                              data-confirm={"Remove #{sub.full_name} as subordinate?"}
                              class="text-danger hover:bg-danger/10 text-xs px-2 py-1"
                            >
                              <.icon name="bilimbi-x-mark" class="size-3.5" />
                              <span class="sr-only">Remove</span>
                            </.button>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </.card>
          <.discovered_panel
            key="employee.addresses"
            id="addresses-panel"
            current_scope={@current_scope}
            opts={%{employee_id: @employee.id}}
          />
          <!-- Danger Zone Card -->
          <div
            :if={@can_delete?}
            id="employee-danger"
            class="rounded-xl border border-line bg-surface px-5 py-4"
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
      </.page>
    </Layouts.app>
    """
  end

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("probation"), do: :warning
  defp status_badge_kind("terminated"), do: :danger
  defp status_badge_kind(_), do: :neutral

  defp display_or_dash(nil), do: "—"
  defp display_or_dash(""), do: "—"
  defp display_or_dash(value), do: to_string(value)

  # The mount-time assign hides controls; it is presentation state. Every
  # write asks again, because a LiveView process outlives its mount and a
  # revoked grant must not keep working until remount (#609, the #482/#541
  # pattern).
  defp can_manage?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @manage_capability).allowed
  end
end
