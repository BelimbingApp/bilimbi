defmodule Bilimbi.Core.Employee.Web.ShowLive do
  @moduledoc """
  Read-first LiveView adapter for one employee in the signed-in company.

  The page shows the employee as facts. An operator holding
  `admin.employee.update` edits each fact in place and a committed edit saves
  by itself; there is no edit mode and no "Edit employee" button, as on
  `/addresses/:id` and `/users/:id` and as Belimbing's `admin/employees/show`
  presents the same record:

  - the text facts (full name, short name, employee number, designation,
    email, mobile number, and the job description of an agent) commit on
    Enter or on leaving the field, through `<.inline_edit>`; Escape cancels.
    Every nullable column passes `allow_empty`, so clearing a short name or
    an email is a real edit; the full name and employee number are required,
    so an emptied input commits nothing;
  - the choice facts (department, supervisor, employee type, status) read as
    a name or a badge with a hover pencil, become a focused select on click,
    commit on change, and Escape or leaving the select cancels. The employee
    type commits through the manifest-declared `employee.accounts` operation
    because Core User owns the account transition that a switch to `agent`
    performs in the same transaction.

  Each fact reports its own outcome through the shared commit status that
  `Bilimbi.Base.UI.CommitStatus` keeps: "Saving…" while the round trip is in
  flight, "Saved" once stored, and an alert on the fact naming the rejected
  value and the validation error when the save was refused. The stored value
  stays on screen until the server confirms a change, and success does not
  flash. The platform orchestrator's identity is refused by the domain, and
  that refusal lands on the fact like any other.

  Facts the page cannot save in place stay read-only: the company (a
  relation Core Company owns), employment start and end (dates, which the
  text editor cannot commit truthfully), and the linked account, subordinates
  and addresses, which are their own workflows — the last two render as
  discovered embeds owned by Core User and Core Address (`employee.accounts`,
  `employee.addresses`); this page names neither module.

  The header is the quiet labelled row Belimbing's page carries — the record
  history disclosure beside the word "History" and a "← Back" link. History
  is that row's button; Back is a link. There is no edit button.

  Every section below it has the anatomy DESIGN.md's "Detail sections and
  facts" sets out: a `<.card>` region opened by `<.section_heading>`, its
  facts the shared `<.list>` (the linked account is one of those rows, its
  value the `employee.accounts` embed) and its subordinates the shared
  `<.table>`, unframed inside the card, sorted by this page, with assigning
  as the heading's own action and removal as a demoted icon action on the
  row. Nothing here hand-writes a heading, a `<dl>` or a `<table>`.

  Deleting the platform orchestrator (`SYS-001` / `agent`) is refused by the
  domain as `:invariant_violation`; this screen reports that honestly rather
  than hiding the row.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.CommitStatus
  alias Bilimbi.Base.UI.DiscoveredPanels
  alias Phoenix.LiveView.JS

  @manage_capability "admin.employee.update"

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee

  # `toggle_add_subordinate`, `edit_field`, and `cancel_edit_field` only flip
  # visibility assigns; the persisting events are `add_subordinate` and the
  # `save_*` family, which are capability-guarded (#420).
  @write_guard_opt_out ~w(toggle_add_subordinate edit_field cancel_edit_field)

  # The facts an inline text edit may write, keyed by the form name the hook
  # pushes. A name outside this map is ignored; user input never becomes an atom.
  @inline_fields %{
    "full_name" => :full_name,
    "short_name" => :short_name,
    "employee_number" => :employee_number,
    "job_description" => :job_description,
    "designation" => :designation,
    "email" => :email,
    "mobile_number" => :mobile_number
  }

  # The text facts whose column is nullable: clearing one is a real edit.
  @nullable_fields ~w(short_name job_description designation email mobile_number)

  # The choice facts and the schema field each one writes.
  @choice_fields %{
    "department" => :department_id,
    "supervisor" => :supervisor_id,
    "employee_type" => :employee_type,
    "status" => :status
  }

  @statuses ~w(pending probation active inactive terminated)

  @fact_labels %{
    "full_name" => "Full Name",
    "short_name" => "Short Name",
    "employee_number" => "Employee Number",
    "job_description" => "Job Description",
    "designation" => "Designation",
    "email" => "Email",
    "mobile_number" => "Mobile Number",
    "department" => "Department",
    "supervisor" => "Supervisor",
    "employee_type" => "Employee Type",
    "status" => "Status"
  }

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
        |> CommitStatus.init()
        |> init_ui_state()
        |> load_data(employee)

      {:ok, socket}
    else
      _ -> {:ok, not_found(socket)}
    end
  end

  defp init_ui_state(socket) do
    socket
    |> assign(:editing_field, nil)
    |> assign(:adding_subordinate, false)
    |> assign(:selected_subordinate_id, "")
    |> assign(:subordinates_sort_by, "full_name")
    |> assign(:subordinates_sort_dir, "asc")
    |> assign(:pending_subordinate, nil)
    |> assign(:pending_delete?, false)
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
    |> assign(:editing_field, nil)
    |> assign(:employee, employee)
    |> assign(:page_title, Employee.Summary.display_name(employee))
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

  defp employee_auditable_types do
    ["Bilimbi.Core.Employee.Schema", "Bilimbi.Core.Employee", Employee.addressable_identity()]
  end

  # --- Event Handlers: Inline Text Facts ---

  # One commit, one outcome on the fact that made it. Every write re-asks
  # Authz; the `can_manage?` assign only decides what the page shows.
  @impl true
  def handle_event("save_field", params, socket) do
    if can_manage?(socket) do
      case CommitStatus.inline_field(params, @inline_fields) do
        {:ok, name, field, value} ->
          {:noreply, save_fact(socket, name, %{field => normalize_param(value)}, value)}

        :error ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # --- Event Handlers: Choice Facts ---

  def handle_event("edit_field", %{"field" => field}, socket)
      when is_map_key(@choice_fields, field) do
    if can_manage?(socket) do
      {:noreply, assign(socket, :editing_field, field)}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("edit_field", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit_field", _params, socket) do
    {:noreply, assign(socket, :editing_field, nil)}
  end

  def handle_event("save_status", params, socket) do
    if can_manage?(socket) do
      status = to_string(params["status"] || "")

      {:noreply,
       save_choice(socket, "status", %{status: status}, choice_label(socket, "status", status))}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("save_department", params, socket) do
    if can_manage?(socket) do
      department_id = parse_optional_id(params["department_id"])

      {:noreply,
       save_choice(
         socket,
         "department",
         %{department_id: department_id},
         choice_label(socket, "department", department_id)
       )}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("save_supervisor", params, socket) do
    if can_manage?(socket) do
      supervisor_id = parse_optional_id(params["supervisor_id"])

      {:noreply,
       save_choice(
         socket,
         "supervisor",
         %{supervisor_id: supervisor_id},
         choice_label(socket, "supervisor", supervisor_id)
       )}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # The manifest-declared account operation owns the cross-module account
  # transition. It is not probing: a missing provider fails honestly, and
  # Core User performs the unlink and Employee write in one transaction.
  def handle_event("save_employee_type", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      type = to_string(params["employee_type"] || "")

      result =
        DiscoveredPanels.dispatch("employee.accounts", :change_employee_type, [
          scope,
          employee.company_id,
          employee.id,
          type
        ])

      {:noreply,
       socket
       |> assign(:editing_field, nil)
       |> commit("employee_type", result, choice_label(socket, "employee_type", type))}
    else
      {:noreply, write_forbidden(socket)}
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
               |> put_flash(:success, "Subordinate assigned.")
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
      {:noreply, write_forbidden(socket)}
    end
  end

  # Removing a subordinate confirms through the shared dialog: the request holds
  # the listed subordinate whose consequence the dialog states, and
  # `remove_subordinate` acts on that held record rather than on a
  # client-supplied id, so what was confirmed is what runs.
  def handle_event("request_remove_subordinate", %{"id" => sub_id_str}, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, write_forbidden(socket)}

      sub = find_subordinate(socket, sub_id_str) ->
        {:noreply, socket |> clear_flash() |> assign(:pending_subordinate, sub)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_remove_subordinate", _params, socket) do
    {:noreply, assign(socket, :pending_subordinate, nil)}
  end

  def handle_event("remove_subordinate", _params, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, write_forbidden(socket)}

      is_nil(socket.assigns.pending_subordinate) ->
        {:noreply, socket}

      true ->
        sub = socket.assigns.pending_subordinate
        socket = assign(socket, :pending_subordinate, nil)
        scope = socket.assigns.current_scope.scope
        employee = socket.assigns.employee

        case Employee.remove_subordinate(scope, employee.company_id, employee.id, sub.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(
               :success,
               "#{sub.full_name} no longer reports to #{employee.full_name}."
             )
             |> load_data(employee)}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "#{sub.full_name} was not removed. Reload the page and try again."
             )}
        end
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

  # Deleting confirms through the shared dialog, which states what happens to
  # this employee's record; `delete` runs only once a request is held.
  def handle_event("request_delete", _params, socket) do
    if socket.assigns.can_delete? do
      {:noreply, socket |> clear_flash() |> assign(:pending_delete?, true)}
    else
      {:noreply, put_flash(socket, :error, "You do not have access to that action.")}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete?, false)}
  end

  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    employee = socket.assigns.employee
    company_id = socket.assigns.current_scope.user["company_id"]

    cond do
      not socket.assigns.can_delete? ->
        {:noreply, put_flash(socket, :error, "You do not have access to that action.")}

      not socket.assigns.pending_delete? ->
        {:noreply, socket}

      true ->
        socket = assign(socket, :pending_delete?, false)

        case Employee.delete_employee(scope, company_id, employee.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:success, "#{employee.full_name} was deleted.")
             |> push_navigate(to: ~p"/employees")}

          {:error, :invariant_violation} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "#{employee.full_name} was not deleted: the platform orchestrator cannot be deleted."
             )}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "#{employee.full_name} was not deleted. Reload the page and try again."
             )}
        end
    end
  end

  # --- Saving ---

  defp find_subordinate(socket, sub_id_str) do
    case Integer.parse(sub_id_str) do
      {sub_id, ""} -> Enum.find(socket.assigns.subordinates, &(&1.id == sub_id))
      _ -> nil
    end
  end

  # A text fact: the write, then the outcome on the fact that made it.
  defp save_fact(socket, name, attrs, submitted) do
    scope = socket.assigns.current_scope.scope
    employee = socket.assigns.employee

    commit(
      socket,
      name,
      Employee.update_employee(scope, employee.company_id, employee.id, attrs),
      submitted
    )
  end

  # A choice fact commits on change and closes its select first, so the
  # outcome — stored or refused — reads beside the read state, as on
  # `/addresses/:id`. Each caller has already re-asked Authz.
  defp save_choice(socket, name, attrs, choice) do
    socket
    |> assign(:editing_field, nil)
    |> save_fact(name, attrs, choice)
  end

  # One commit, one outcome. Success reloads the page's projections (title,
  # subtitle, supervisor and subordinate lists) from the server; refusal keeps
  # the stored value on screen and says what was rejected and why.
  defp commit(socket, name, result, submitted) do
    case result do
      {:ok, updated_employee} ->
        socket
        |> load_data(updated_employee)
        |> CommitStatus.put(name, :saved)

      {:error, %Ecto.Changeset{} = changeset} ->
        CommitStatus.put(socket, name, {:error, refusal_message(name, submitted, changeset)})

      {:error, reason} ->
        CommitStatus.put(socket, name, {:error, failure_message(reason, submitted)})
    end
  end

  # A choice fact reports on the schema field it writes; the shared wording
  # names the rejected value and the label.
  defp refusal_message(name, submitted, %Ecto.Changeset{} = changeset) do
    field = Map.get(@inline_fields, name) || Map.fetch!(@choice_fields, name)
    CommitStatus.refusal_message(fact_label(name), field, submitted, changeset.errors)
  end

  defp failure_message(:employee_not_found, _submitted),
    do: "This employee no longer exists. Return to the list to find their replacement."

  defp failure_message(:company_not_found, _submitted),
    do: "The change was not saved because this employee's company could not be found."

  # The domain refuses the change outright for the platform orchestrator
  # (`SYS-001` / `agent`); the fact says so rather than a generic sentence.
  defp failure_message(:invariant_violation, submitted),
    do:
      "#{inspect(CommitStatus.rejected_value(submitted))} was not saved: " <>
        "the platform orchestrator's identity is protected."

  defp failure_message(_reason, _submitted), do: CommitStatus.failure_message()

  defp write_forbidden(socket),
    do: CommitStatus.write_forbidden(socket, "You do not have permission to edit employees.")

  # What the operator chose, as the alert names it: the option's visible
  # label when it came from this page's list, "None" for the blank option,
  # and the raw value for anything else.
  defp choice_label(_socket, name, nil) when name in ["department", "supervisor"], do: "None"

  defp choice_label(socket, "department", id),
    do: Map.get(socket.assigns.department_map, id, Integer.to_string(id))

  defp choice_label(socket, "supervisor", id),
    do: Map.get(socket.assigns.supervisor_map, id, Integer.to_string(id))

  defp choice_label(socket, "employee_type", code),
    do: employee_type_label(socket.assigns.employee_types, code)

  defp choice_label(_socket, "status", status) when status in @statuses,
    do: String.capitalize(status)

  defp choice_label(_socket, "status", status), do: status

  defp fact_label(name), do: Map.fetch!(@fact_labels, name)

  defp parse_optional_id(value) do
    case Integer.parse(to_string(value || "")) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  # A trimmed, emptied value writes NULL; the required columns then refuse it
  # as blank, and the nullable ones clear.
  defp normalize_param(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_param(other), do: other

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

  # --- Fact Components ---

  # The value cell of a read-first text fact — the row itself, its label and
  # its `employee-view-*` id are the shared `<.list>` item that renders it. An
  # operator who may update edits it in place and the fact reports its own
  # outcome; a nullable column may be emptied. Anyone else sees the stored
  # value with no affordance.
  attr(:name, :string, required: true)
  attr(:employee, :map, required: true)
  attr(:can_manage?, :boolean, required: true)
  attr(:field_status, :map, required: true)
  attr(:class, :any, default: nil)

  defp text_fact(assigns) do
    assigns =
      assigns
      |> assign(:label, fact_label(assigns.name))
      |> assign(:value, Map.fetch!(assigns.employee, Map.fetch!(@inline_fields, assigns.name)))
      |> assign(:allow_empty?, assigns.name in @nullable_fields)
      |> assign(:dom_id, fact_dom_id(assigns.name))

    ~H"""
    <.inline_edit
      :if={@can_manage?}
      id={@dom_id}
      name={@name}
      label={@label}
      value={@value || ""}
      id_value={@employee.id}
      save_event="save_field"
      allow_empty={@allow_empty?}
      status={@field_status[@name]}
      class={@class}
    />
    <span :if={not @can_manage?} class={[is_nil(@value) && "text-ink-muted", @class]}>
      {@value || "—"}
    </span>
    """
  end

  # `employee-number` keeps the id Belimbing gives the same fact; every other
  # fact derives its id from its name.
  defp fact_dom_id("employee_number"), do: "employee-number"
  defp fact_dom_id(name), do: "employee-" <> String.replace(name, "_", "-")

  # Edit-in-place shell for the employment-info selects (#619): managers see
  # the read state (badge, name, or link — the scan layer a raw `<select>`
  # loses) with a hover pencil; clicking swaps in the `:editor` slot, whose
  # `save_*` form commits on change and closes it. Escape or blur cancels.
  # Read-only visitors get the `:display` slot without the trigger. The
  # outcome of the last commit renders beneath, on the fact that made it.
  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:editing, :boolean, required: true)
  attr(:can_manage?, :boolean, required: true)
  attr(:status, :any, required: true)
  slot(:display, required: true)
  slot(:editor, required: true)

  defp choice_fact(assigns) do
    ~H"""
    <.inline_choice
      id={"employee-#{@field}"}
      field={@field}
      label={@label}
      editing={@editing}
      editable?={@can_manage?}
      status={@status}
      status_id={"#{fact_dom_id(@field)}-status"}
    >
      <:display>{render_slot(@display)}</:display>
      <:editor>{render_slot(@editor)}</:editor>
    </.inline_choice>
    """
  end

  # --- Render Template ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          {Employee.Summary.display_name(@employee)}
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin this employee to sidebar"
              context={:inline}
              id="employee-pin"
              data-nav-pin="record"
              data-nav-pin-record="true"
              data-nav-pin-label={"Administration / Employees / #{Employee.Summary.display_name(@employee)}"}
              data-nav-pin-url={~p"/employees/#{@employee.id}"}
              aria-pressed="false"
            />
          </:title_actions>
          <:subtitle>
            {@employee.designation || @employee.job_description || @employee.employee_number}
          </:subtitle>

          <:actions>
            <%!-- Belimbing's admin/employees/show header: History and Back as
                 one quiet labelled row, each glyph beside its word, and no
                 button. The row wraps at narrow widths instead of clipping. --%>
            <div class="flex flex-wrap items-center gap-3">
              <.discovered_panel
                key="record.history"
                id="employee-record-history"
                current_scope={@current_scope}
                opts={
                  %{
                    auditable_types: employee_auditable_types(),
                    auditable_id: @employee.id,
                    record: @employee
                  }
                }
              />
              <.back_link id="employee-back" navigate={~p"/employees"} title="Back to employees" />
            </div>
          </:actions>
        </.header>

        <div class="mt-6 space-y-6">
          <%!-- Section 1: Employee Details. The facts are the shared `<.list>`
               under the shared `<.section_heading>`, as on `/companies/:id` and
               `/addresses/:id`; each fact edits in place and reports on
               itself, so the heading carries no button. --%>
          <.card
            id="employee-details-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="employee-details-heading"
          >
            <.section_heading id="employee-details-heading" title="Employee Details" />

            <.list id="employee-details">
              <:item title={fact_label("full_name")} id="employee-view-full-name">
                <.text_fact
                  name="full_name"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                />
              </:item>
              <:item title={fact_label("short_name")} id="employee-view-short-name">
                <.text_fact
                  name="short_name"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                />
              </:item>
              <:item title={fact_label("employee_number")} id="employee-view-employee-number">
                <.text_fact
                  name="employee_number"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                  class="font-mono"
                />
              </:item>
              <:item
                :if={@employee.employee_type == "agent"}
                title={fact_label("job_description")}
                id="employee-view-job-description"
              >
                <.text_fact
                  name="job_description"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                />
              </:item>
              <:item title={fact_label("designation")} id="employee-view-designation">
                <.text_fact
                  name="designation"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                />
              </:item>
              <:item title={fact_label("email")} id="employee-view-email">
                <.text_fact
                  name="email"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                />
              </:item>
              <:item title={fact_label("mobile_number")} id="employee-view-mobile-number">
                <.text_fact
                  name="mobile_number"
                  employee={@employee}
                  can_manage?={@can_manage?}
                  field_status={@field_status}
                />
              </:item>
            </.list>
          </.card>

          <%!-- Section 2: Employment Information. The linked account is a fact
               of the same list; its value is the discovered `employee.accounts`
               embed Core User owns, and an agent has no account row. --%>
          <.card
            id="employment-info-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="employment-info-heading"
          >
            <.section_heading id="employment-info-heading" title="Employment Information" />

            <.list id="employment-info">
              <:item title="Company" id="employee-view-company">
                {@company_name}
              </:item>

              <:item title="Department" id="employee-view-department">
                <.choice_fact
                  field="department"
                  label="Edit department"
                  editing={@editing_field == "department"}
                  can_manage?={@can_manage?}
                  status={@field_status["department"]}
                >
                  <:display>
                    <span class={[
                      "truncate",
                      is_nil(@employee.department_id) && "text-ink-muted"
                    ]}>
                      {Map.get(@department_map, @employee.department_id, "None")}
                    </span>
                  </:display>
                  <:editor>
                    <form
                      phx-change="save_department"
                      id="employee-department-form"
                      class="inline-block"
                    >
                      <select
                        id="employee-department"
                        name="department_id"
                        aria-label="Department"
                        phx-mounted={JS.focus()}
                        phx-blur="cancel_edit_field"
                        class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                      >
                        <option value="" selected={is_nil(@employee.department_id)}>None</option>

                        <%= for dept <- @departments do %>
                          <option value={dept.id} selected={@employee.department_id == dept.id}>
                            {if dept.type, do: dept.type.name, else: "Department #{dept.id}"}
                          </option>
                        <% end %>
                      </select>
                    </form>
                  </:editor>
                </.choice_fact>
              </:item>

              <:item title="Supervisor" id="employee-view-supervisor">
                <.choice_fact
                  field="supervisor"
                  label="Edit supervisor"
                  editing={@editing_field == "supervisor"}
                  can_manage?={@can_manage?}
                  status={@field_status["supervisor"]}
                >
                  <:display>
                    <span class={[
                      "truncate",
                      is_nil(@employee.supervisor_id) && "text-ink-muted"
                    ]}>
                      {Map.get(@supervisor_map, @employee.supervisor_id, "None")}
                    </span>
                  </:display>
                  <:editor>
                    <form
                      phx-change="save_supervisor"
                      id="employee-supervisor-form"
                      class="inline-block"
                    >
                      <select
                        id="employee-supervisor"
                        name="supervisor_id"
                        aria-label="Supervisor"
                        phx-mounted={JS.focus()}
                        phx-blur="cancel_edit_field"
                        class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                      >
                        <option value="" selected={is_nil(@employee.supervisor_id)}>None</option>

                        <%= for sup <- @supervisors do %>
                          <option value={sup.id} selected={@employee.supervisor_id == sup.id}>
                            {sup.full_name}
                          </option>
                        <% end %>
                      </select>
                    </form>
                  </:editor>
                </.choice_fact>
              </:item>

              <:item title="Employee Type" id="employee-view-employee-type">
                <.choice_fact
                  field="employee_type"
                  label="Edit employee type"
                  editing={@editing_field == "employee_type"}
                  can_manage?={@can_manage?}
                  status={@field_status["employee_type"]}
                >
                  <:display>
                    <%!-- Neutral for every type, matching the index table
                         (same thing, same look); status alone carries color. --%>
                    <.badge kind={:neutral}>
                      {employee_type_label(@employee_types, @employee.employee_type)}
                    </.badge>
                  </:display>
                  <:editor>
                    <form
                      phx-change="save_employee_type"
                      id="employee-type-form"
                      class="inline-block"
                    >
                      <select
                        id="employee-type"
                        name="employee_type"
                        aria-label="Employee type"
                        phx-mounted={JS.focus()}
                        phx-blur="cancel_edit_field"
                        class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
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
                  </:editor>
                </.choice_fact>
              </:item>

              <:item title="Status" id="employee-view-status">
                <.choice_fact
                  field="status"
                  label="Edit status"
                  editing={@editing_field == "status"}
                  can_manage?={@can_manage?}
                  status={@field_status["status"]}
                >
                  <:display>
                    <.badge kind={status_badge_kind(@employee.status)}>
                      {String.capitalize(@employee.status)}
                    </.badge>
                  </:display>
                  <:editor>
                    <form phx-change="save_status" id="employee-status-form" class="inline-block">
                      <select
                        id="employee-status"
                        name="status"
                        aria-label="Status"
                        phx-mounted={JS.focus()}
                        phx-blur="cancel_edit_field"
                        class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                      >
                        <option
                          :for={status <- statuses()}
                          value={status}
                          selected={@employee.status == status}
                        >
                          {String.capitalize(status)}
                        </option>
                      </select>
                    </form>
                  </:editor>
                </.choice_fact>
              </:item>

              <:item :if={@employee.employee_type != "agent"} title="User" id="employee-view-user">
                <.discovered_panel
                  key="employee.accounts"
                  id="account-panel"
                  current_scope={@current_scope}
                  opts={%{employee_id: @employee.id, company_id: @employee.company_id}}
                />
              </:item>

              <:item title="Employment Start" id="employee-view-employment-start">
                <span class="tabular-nums">
                  <.datetime
                    id="employee-employment-start"
                    value={@employee.employment_start}
                    format={:date}
                  />
                </span>
              </:item>

              <:item title="Employment End" id="employee-view-employment-end">
                <span class="tabular-nums">
                  <.datetime
                    id="employee-employment-end"
                    value={@employee.employment_end}
                    format={:date}
                  />
                </span>
              </:item>
            </.list>
          </.card>

          <%!-- Section 3: Subordinates. The shared table, unframed inside the
               section card, sorted by the page; assigning is the section's
               own action in the heading row and removing is a demoted icon
               action on the row. --%>
          <.card
            id="subordinates-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="employee-subordinates-heading"
          >
            <.section_heading
              id="employee-subordinates-heading"
              title="Subordinates"
              count={length(@subordinates)}
            >
              <:actions :if={@can_manage?}>
                <%= if @adding_subordinate do %>
                  <form
                    phx-submit="add_subordinate"
                    id="add-subordinate-form"
                    class="flex flex-wrap items-center gap-2"
                  >
                    <select
                      id="employee-subordinate-select"
                      name="subordinate_id"
                      aria-label="Employee to assign"
                      class="min-w-48 rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
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
                    <.icon name="create" class="size-3.5" /> <span>Add</span>
                  </.button>
                <% end %>
              </:actions>
            </.section_heading>

            <.table
              id="subordinates-table"
              rows={@sorted_subordinates}
              row_id={fn sub -> "subordinate-row-#{sub.id}" end}
              sort_by={@subordinates_sort_by}
              sort_dir={@subordinates_sort_dir}
              sort_event="sort_subordinates"
              caption="Subordinates"
              framed={false}
            >
              <:col :let={sub} label="Name" sort="full_name">
                <.link
                  id={"subordinate-link-#{sub.id}"}
                  navigate={~p"/employees/#{sub.id}"}
                  class="font-medium text-action hover:underline"
                >
                  {sub.full_name}
                </.link>
              </:col>
              <:col :let={sub} label="Designation" sort="designation">
                <span class="text-ink-subtle">{display_or_dash(sub.designation)}</span>
              </:col>
              <:col :let={sub} label="Status" sort="status">
                <.badge kind={status_badge_kind(sub.status)}>
                  {String.capitalize(sub.status)}
                </.badge>
              </:col>
              <:col :let={sub} label="Department" sort="department">
                <span class="text-ink-subtle">
                  {Map.get(@department_map, sub.department_id, "—")}
                </span>
              </:col>
              <:action :let={sub}>
                <.icon_button
                  :if={@can_manage?}
                  icon="close"
                  label={"Remove #{sub.full_name} as subordinate"}
                  kind={:danger}
                  id={"remove-subordinate-#{sub.id}"}
                  phx-click="request_remove_subordinate"
                  phx-value-id={sub.id}
                />
              </:action>
              <:empty
                :if={@sorted_subordinates == []}
                title="No subordinates"
                reason="Employees who report to this employee appear here."
              />
            </.table>
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

              <.button id="employee-delete" variant="danger" phx-click="request_delete">
                Delete employee
              </.button>
            </div>
          </div>
        </div>

        <.confirm_dialog
          :if={@pending_subordinate}
          id="remove-subordinate-confirm"
          consequence={"#{@pending_subordinate.full_name} will no longer report to #{@employee.full_name}."}
          detail="Both employee records are kept. The reporting line can be set again."
          confirm="Remove"
          working="Removing…"
          on_confirm={JS.push("remove_subordinate")}
          on_cancel={JS.push("cancel_remove_subordinate")}
        />

        <.confirm_dialog
          :if={@pending_delete?}
          id="delete-employee-confirm"
          consequence={"#{@employee.full_name} will be deleted."}
          detail="The employment record is removed and the person no longer appears in the directory. This cannot be undone."
          confirm="Delete"
          working="Deleting…"
          on_confirm={JS.push("delete")}
          on_cancel={JS.push("cancel_delete")}
        />
      </.page>
    </Layouts.app>
    """
  end

  defp statuses, do: @statuses

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("probation"), do: :warning
  defp status_badge_kind("terminated"), do: :danger
  defp status_badge_kind(_), do: :neutral

  defp employee_type_label(types, code) do
    case Enum.find(types, &(&1.code == code)) do
      %{label: label} when is_binary(label) -> label
      _ -> code |> String.replace("_", " ") |> String.capitalize()
    end
  end

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
