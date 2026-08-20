defmodule Bilimbi.Core.Employee.Web.ShowLive do
  @moduledoc """
  Shows one employee in the signed-in company and provides administrative management:
  in-place field editing, lifecycle status and type selection, department/supervisor
  assignments, user account linking, direct subordinates management with sortable table,
  and address attachments.

  Deleting the platform orchestrator (`SYS-001` / `agent`) is refused by the domain as
  `:invariant_violation`; this screen reports that honestly rather than hiding the row.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee

  @valid_address_kinds ~w(headquarters billing shipping branch other)

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
    |> assign(:addresses_sort_by, "label")
    |> assign(:addresses_sort_dir, "asc")
    |> assign(:show_attach_modal, false)
    |> assign(:editing_kinds_address_id, nil)
    |> assign(:selected_edit_kinds, [])
    |> assign(:editing_priority_address_id, nil)
    |> assign(:edit_priority_value, "0")
    |> assign(
      :attach_form,
      to_form(%{
        "address_id" => "",
        "kinds" => [],
        "is_primary" => false,
        "priority" => "0"
      })
    )
    |> assign(:attach_errors, %{})
  end

  defp load_data(socket, employee) do
    scope = socket.assigns.current_scope.scope
    current_scope = socket.assigns.current_scope
    can_manage? = allowed?(current_scope, "admin.employee.update")
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

    # Users (dynamic dispatch)
    company_users = list_company_users(scope, company_id)
    linked_user = Enum.find(company_users, &(&1.employee_id == employee.id))

    available_users =
      Enum.filter(company_users, &(is_nil(&1.employee_id) or &1.employee_id == employee.id))

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

    # Addresses (dynamic dispatch)
    attached_addresses = list_employee_attached_addresses(scope, employee.id)
    available_addresses = list_available_employee_addresses(scope, employee.id)

    sorted_addresses =
      sort_addresses(
        attached_addresses,
        socket.assigns.addresses_sort_by,
        socket.assigns.addresses_sort_dir
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
    |> assign(:company_users, company_users)
    |> assign(:linked_user, linked_user)
    |> assign(:available_users, available_users)
    |> assign(:subordinates, subordinates)
    |> assign(:available_subordinates, available_subordinates)
    |> assign(:sorted_subordinates, sorted_subordinates)
    |> assign(:attached_addresses, attached_addresses)
    |> assign(:available_addresses, available_addresses)
    |> assign(:sorted_addresses, sorted_addresses)
    |> assign(:address_kinds, @valid_address_kinds)
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That employee does not exist in this company.")
    |> push_navigate(to: ~p"/employees")
  end

  # --- Event Handlers: Inline Editing of Text Fields ---

  @impl true
  def handle_event("save_field", params, socket) do
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      type = params["employee_type"] || params["value"] || ""

      # An agent holds no user account, so switching to agent unlinks one. If that
      # unlink fails the type change must not proceed — it is what makes the
      # invariant true.
      unlink =
        if type == "agent" and not is_nil(socket.assigns.linked_user) do
          update_user_employee_id(scope, employee.company_id, socket.assigns.linked_user.id, nil)
        else
          {:ok, nil}
        end

      result =
        with {:ok, _} <- unlink do
          Employee.update_employee(scope, employee.company_id, employee.id, %{
            employee_type: type
          })
        end

      case result do
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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

  def handle_event("save_user", params, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      current_linked = socket.assigns.linked_user

      user_id_val = params["user_id"] || params["value"] || ""

      target_user_id =
        case Integer.parse(to_string(user_id_val)) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      # Unlink the current user first. A failure here has to stop the link:
      # carrying on would leave two users pointing at this employee.
      unlink =
        if current_linked && current_linked.id != target_user_id do
          update_user_employee_id(scope, employee.company_id, current_linked.id, nil)
        else
          {:ok, nil}
        end

      result =
        with {:ok, _} <- unlink do
          if target_user_id do
            update_user_employee_id(scope, employee.company_id, target_user_id, employee.id)
          else
            {:ok, nil}
          end
        end

      case result do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "User link updated.")
           |> load_data(employee)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update linked user account.")}
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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

  # --- Event Handlers: Addresses ---

  def handle_event("open_attach_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_attach_modal, true)
     |> assign(
       :attach_form,
       to_form(%{
         "address_id" => "",
         "kinds" => [],
         "is_primary" => false,
         "priority" => "0"
       })
     )
     |> assign(:attach_errors, %{})}
  end

  def handle_event("close_attach_modal", _params, socket) do
    {:noreply, assign(socket, :show_attach_modal, false)}
  end

  def handle_event("attach_address", params, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      addr_params = params["address"] || params
      address_id_str = addr_params["address_id"] || ""

      kinds =
        case addr_params["kinds"] do
          list when is_list(list) -> Enum.filter(list, &(&1 in @valid_address_kinds))
          str when is_binary(str) and str != "" -> [str]
          _ -> []
        end

      is_primary = addr_params["is_primary"] in [true, "true", "1", 1]

      priority_int =
        case Integer.parse(to_string(addr_params["priority"] || "0")) do
          {p, ""} when p >= 0 -> p
          _ -> 0
        end

      case parse_id(address_id_str) do
        address_id when is_integer(address_id) and address_id > 0 ->
          attrs = %{
            kind: kinds,
            is_primary: is_primary,
            priority: priority_int
          }

          case attach_address_to_employee(scope, address_id, employee.id, attrs) do
            {:ok, :attached} ->
              {:noreply,
               socket
               |> put_flash(:info, "Address attached.")
               |> assign(:show_attach_modal, false)
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to attach address.")}
          end

        _ ->
          {:noreply,
           socket
           |> assign(:attach_errors, %{address_id: "Please select an address."})
           |> assign(:attach_form, to_form(addr_params))}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("detach_address", %{"id" => address_id_str}, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      case parse_id(address_id_str) do
        address_id when is_integer(address_id) and address_id > 0 ->
          case detach_address_from_employee(scope, address_id, employee.id) do
            :ok ->
              {:noreply,
               socket
               |> put_flash(:info, "Address unlinked.")
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to unlink address.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("toggle_address_primary", %{"id" => address_id_str}, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      case parse_id(address_id_str) do
        address_id when is_integer(address_id) and address_id > 0 ->
          target_addr = Enum.find(socket.assigns.attached_addresses, &(&1.id == address_id))
          new_primary = if target_addr, do: not target_addr.is_primary, else: true

          case update_employee_address_attachment(scope, address_id, employee.id, %{
                 is_primary: new_primary
               }) do
            {:ok, :updated} ->
              {:noreply,
               socket
               |> put_flash(:info, "Address setting updated.")
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update address setting.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("edit_address_priority", %{"id" => address_id_str}, socket) do
    case parse_id(address_id_str) do
      address_id when is_integer(address_id) and address_id > 0 ->
        target_addr = Enum.find(socket.assigns.attached_addresses, &(&1.id == address_id))
        val = if target_addr, do: to_string(target_addr.priority), else: "0"

        {:noreply,
         socket
         |> assign(:editing_priority_address_id, address_id)
         |> assign(:edit_priority_value, val)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_address_priority", _params, socket) do
    {:noreply, assign(socket, :editing_priority_address_id, nil)}
  end

  def handle_event("save_address_priority", params, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee

      address_id =
        socket.assigns.editing_priority_address_id || params["address_id"] || params["id"]

      prio_val = params["priority"] || params["value"] || "0"

      priority_int =
        case Integer.parse(to_string(prio_val)) do
          {p, ""} when p >= 0 -> p
          _ -> 0
        end

      case parse_id(address_id) do
        id when is_integer(id) and id > 0 ->
          case update_employee_address_attachment(scope, id, employee.id, %{
                 priority: priority_int
               }) do
            {:ok, :updated} ->
              {:noreply,
               socket
               |> put_flash(:info, "Address setting updated.")
               |> assign(:editing_priority_address_id, nil)
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update priority.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("edit_address_kinds", %{"id" => address_id_str}, socket) do
    case parse_id(address_id_str) do
      address_id when is_integer(address_id) and address_id > 0 ->
        target_addr = Enum.find(socket.assigns.attached_addresses, &(&1.id == address_id))
        kinds = if target_addr, do: target_addr.kind || [], else: []

        {:noreply,
         socket
         |> assign(:editing_kinds_address_id, address_id)
         |> assign(:selected_edit_kinds, kinds)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_address_kinds", _params, socket) do
    {:noreply, assign(socket, :editing_kinds_address_id, nil)}
  end

  def handle_event("toggle_edit_kind", %{"kind" => kind}, socket) do
    current = socket.assigns.selected_edit_kinds

    updated =
      if kind in current do
        List.delete(current, kind)
      else
        [kind | current]
      end

    {:noreply, assign(socket, :selected_edit_kinds, updated)}
  end

  def handle_event("save_address_kinds", params, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      employee = socket.assigns.employee
      address_id = socket.assigns.editing_kinds_address_id || params["address_id"] || params["id"]

      kinds =
        case params["kinds"] do
          list when is_list(list) -> Enum.filter(list, &(&1 in @valid_address_kinds))
          _ -> socket.assigns.selected_edit_kinds
        end

      case parse_id(address_id) do
        id when is_integer(id) and id > 0 ->
          case update_employee_address_attachment(scope, id, employee.id, %{kind: kinds}) do
            {:ok, :updated} ->
              {:noreply,
               socket
               |> put_flash(:info, "Address kinds updated.")
               |> assign(:editing_kinds_address_id, nil)
               |> load_data(employee)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update address kinds.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit employees.")}
    end
  end

  def handle_event("sort_addresses", params, socket) do
    sort_col = params["sort_by"] || params["sort"] || "label"
    current_dir = socket.assigns.addresses_sort_dir
    current_col = socket.assigns.addresses_sort_by

    new_dir =
      if current_col == sort_col and current_dir == "asc" do
        "desc"
      else
        "asc"
      end

    sorted =
      sort_addresses(
        socket.assigns.attached_addresses,
        sort_col,
        new_dir
      )

    {:noreply,
     socket
     |> assign(:addresses_sort_by, sort_col)
     |> assign(:addresses_sort_dir, new_dir)
     |> assign(:sorted_addresses, sorted)}
  end

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

  # These helpers reach Core.User and Core.Address without a declared dependency,
  # so `Code.ensure_loaded?/1` and `function_exported?/3` answer "is the module
  # installed" and the `else` branch is the honest answer when it is not.
  #
  # There is deliberately no `rescue` around the `apply/3`. Once those two guards
  # pass the function exists, so a raise can only come from inside the callee — a
  # missing table, a constraint, a bug — and that is precisely what must reach the
  # caller. A `rescue _ -> {:ok, nil}` here reported a failed write as a
  # successful one (#409), and a `rescue _ -> []` renders a broken section as an
  # empty one, which is how #359 stayed green in CI.

  defp list_company_users(scope, company_id) do
    user_mod = Bilimbi.Core.User

    if Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :list_company_users, 2) do
      case apply(user_mod, :list_company_users, [scope, company_id]) do
        {:ok, users} -> users
        _ -> []
      end
    else
      []
    end
  end

  defp update_user_employee_id(scope, company_id, user_id, employee_id) do
    user_mod = Bilimbi.Core.User

    if Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :update_user, 4) do
      apply(user_mod, :update_user, [scope, company_id, user_id, %{employee_id: employee_id}])
    else
      {:error, :not_available}
    end
  end

  defp list_employee_attached_addresses(scope, employee_id) do
    addr_mod = Bilimbi.Core.Address

    if Code.ensure_loaded?(addr_mod) and
         function_exported?(addr_mod, :list_employee_attached_addresses, 2) do
      case apply(addr_mod, :list_employee_attached_addresses, [scope, employee_id]) do
        {:ok, addrs} -> addrs
        _ -> []
      end
    else
      []
    end
  end

  defp list_available_employee_addresses(scope, employee_id) do
    addr_mod = Bilimbi.Core.Address

    if Code.ensure_loaded?(addr_mod) and
         function_exported?(addr_mod, :list_available_employee_addresses, 2) do
      case apply(addr_mod, :list_available_employee_addresses, [scope, employee_id]) do
        {:ok, addrs} -> addrs
        _ -> []
      end
    else
      []
    end
  end

  defp attach_address_to_employee(scope, address_id, employee_id, attrs) do
    addr_mod = Bilimbi.Core.Address

    if Code.ensure_loaded?(addr_mod) and function_exported?(addr_mod, :attach_to_employee, 4) do
      apply(addr_mod, :attach_to_employee, [scope, address_id, employee_id, attrs])
    else
      {:error, :not_available}
    end
  end

  defp detach_address_from_employee(scope, address_id, employee_id) do
    addr_mod = Bilimbi.Core.Address

    if Code.ensure_loaded?(addr_mod) and function_exported?(addr_mod, :detach_from_employee, 3) do
      apply(addr_mod, :detach_from_employee, [scope, address_id, employee_id])
    else
      {:error, :not_available}
    end
  end

  defp update_employee_address_attachment(scope, address_id, employee_id, attrs) do
    addr_mod = Bilimbi.Core.Address

    if Code.ensure_loaded?(addr_mod) and
         function_exported?(addr_mod, :update_employee_attachment, 4) do
      apply(addr_mod, :update_employee_attachment, [scope, address_id, employee_id, attrs])
    else
      {:error, :not_available}
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

  defp sort_addresses(addresses, sort_by, sort_dir) do
    mult = if sort_dir == "desc", do: -1, else: 1

    Enum.sort(addresses, fn a, b ->
      case sort_by do
        "label" ->
          compare_strings(a.label || "", b.label || "", mult, a.id, b.id)

        "line1" ->
          compare_strings(a.line1 || "", b.line1 || "", mult, a.id, b.id)

        "kind" ->
          kinds_a = Enum.join(Enum.sort(a.kind || []), ",")
          kinds_b = Enum.join(Enum.sort(b.kind || []), ",")
          compare_strings(kinds_a, kinds_b, mult, a.id, b.id)

        "is_primary" ->
          val_a = if a.is_primary, do: 1, else: 0
          val_b = if b.is_primary, do: 1, else: 0
          compare_integers(val_a, val_b, mult, a.id, b.id)

        "priority" ->
          compare_integers(a.priority || 0, b.priority || 0, mult, a.id, b.id)

        "valid_from" ->
          str_a = if a.valid_from, do: Date.to_iso8601(a.valid_from), else: ""
          str_b = if b.valid_from, do: Date.to_iso8601(b.valid_from), else: ""
          compare_strings(str_a, str_b, mult, a.id, b.id)

        "valid_to" ->
          str_a = if a.valid_to, do: Date.to_iso8601(a.valid_to), else: ""
          str_b = if b.valid_to, do: Date.to_iso8601(b.valid_to), else: ""
          compare_strings(str_a, str_b, mult, a.id, b.id)

        _ ->
          compare_strings(a.label || "", b.label || "", mult, a.id, b.id)
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

  defp compare_integers(a, b, mult, id_a, id_b) do
    case {a, b} do
      {x, y} when x == y ->
        id_a <= id_b

      {x, y} ->
        cmp = if x < y, do: -1, else: 1
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

                <%= if @employee.employee_type != "agent" do %>
                  <div>
                    <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                      User
                    </dt>

                    <dd class="mt-0.5 text-sm text-ink">
                      <%= if @can_manage? do %>
                        <form
                          phx-change="save_user"
                          id="employee-user-form"
                          class="inline-flex items-center gap-2"
                        >
                          <select
                            id="employee-user"
                            name="user_id"
                            class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                          >
                            <option value="" selected={is_nil(@linked_user)}>None</option>

                            <%= for u <- @available_users do %>
                              <option value={u.id} selected={@linked_user && @linked_user.id == u.id}>
                                {u.name}
                              </option>
                            <% end %>
                          </select>

                          <%= if @linked_user do %>
                            <.link
                              navigate={~p"/users/#{@linked_user.id}"}
                              class="text-xs font-medium text-brand-strong hover:underline"
                            >
                              {@linked_user.name}
                            </.link>
                          <% end %>
                        </form>
                      <% else %>
                        <%= if @linked_user do %>
                          <.link
                            navigate={~p"/users/#{@linked_user.id}"}
                            class="text-sm text-brand-strong hover:underline"
                          >
                            {@linked_user.name}
                          </.link>
                        <% else %>
                          <span class="text-sm text-ink-subtle">None</span>
                        <% end %>
                      <% end %>
                    </dd>
                  </div>
                <% end %>

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
          <!-- Card 4: Attached Addresses -->
          <.card id="addresses-card">
            <div class="p-5 sm:p-6 space-y-4">
              <div class="flex items-center justify-between">
                <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle flex items-center gap-1.5">
                  <span>Addresses</span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink">
                    {length(@attached_addresses)}
                  </span>
                </h3>

                <.button
                  :if={@can_manage?}
                  id="btn-open-attach-address"
                  phx-click="open_attach_modal"
                  variant="primary"
                  class="text-xs px-2.5 py-1"
                >
                  <.icon name="bilimbi-plus" class="size-3.5" /> <span>Attach Address</span>
                </.button>
              </div>

              <div class="overflow-x-auto">
                <table id="addresses-table" class="w-full text-left text-xs text-ink">
                  <thead>
                    <tr class="border-b border-line text-ink-subtle">
                      <th class="py-2 pr-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="label"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Label</span>
                          <%= if @addresses_sort_by == "label" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="line1"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Address</span>
                          <%= if @addresses_sort_by == "line1" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="kind"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Kind</span>
                          <%= if @addresses_sort_by == "kind" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="is_primary"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Primary</span>
                          <%= if @addresses_sort_by == "is_primary" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="priority"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Priority</span>
                          <%= if @addresses_sort_by == "priority" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="valid_from"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Valid From</span>
                          <%= if @addresses_sort_by == "valid_from" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses"
                          phx-value-sort_by="valid_to"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Valid To</span>
                          <%= if @addresses_sort_by == "valid_to" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th :if={@can_manage?} class="py-2 pl-3 text-right font-semibold">Actions</th>
                    </tr>
                  </thead>

                  <tbody class="divide-y divide-line">
                    <%= if @sorted_addresses == [] do %>
                      <tr>
                        <td
                          colspan={if @can_manage?, do: 8, else: 7}
                          class="py-6 text-center text-ink-subtle"
                        >
                          No addresses linked.
                        </td>
                      </tr>
                    <% else %>
                      <%= for addr <- @sorted_addresses do %>
                        <tr
                          id={"address-row-#{addr.id}"}
                          class="hover:bg-surface-sunken/40 transition"
                        >
                          <td class="py-2 pr-3 font-medium text-ink">
                            <span>{addr.label || "Address #{addr.id}"}</span>
                          </td>

                          <td class="py-2 px-3 text-ink-subtle">
                            {format_address_summary(addr)}
                          </td>

                          <td class="py-2 px-3">
                            <%= if @editing_kinds_address_id == addr.id do %>
                              <div class="space-y-1">
                                <%= for k <- @address_kinds do %>
                                  <label class="flex items-center gap-1.5 text-xs cursor-pointer">
                                    <input
                                      type="checkbox"
                                      value={k}
                                      checked={k in @selected_edit_kinds}
                                      phx-click="toggle_edit_kind"
                                      phx-value-kind={k}
                                      class="rounded border-line"
                                    /> <span>{String.capitalize(k)}</span>
                                  </label>
                                <% end %>

                                <div class="flex items-center gap-1 pt-1">
                                  <.button
                                    id={"save-kinds-#{addr.id}"}
                                    type="button"
                                    phx-click="save_address_kinds"
                                    phx-value-address_id={addr.id}
                                    variant="primary"
                                    class="text-xs px-2 py-0.5"
                                  >
                                    Save
                                  </.button>

                                  <.button
                                    id={"cancel-kinds-#{addr.id}"}
                                    type="button"
                                    phx-click="cancel_address_kinds"
                                    class="text-xs px-2 py-0.5"
                                  >
                                    Cancel
                                  </.button>
                                </div>
                              </div>
                            <% else %>
                              <div
                                phx-click={if @can_manage?, do: "edit_address_kinds"}
                                phx-value-id={addr.id}
                                class={[
                                  "flex flex-wrap gap-1 items-center",
                                  @can_manage? && "cursor-pointer hover:opacity-80"
                                ]}
                              >
                                <%= if addr.kind == [] do %>
                                  <span class="text-ink-subtle">—</span>
                                <% else %>
                                  <%= for k <- addr.kind do %>
                                    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink border border-line">
                                      {String.capitalize(k)}
                                    </span>
                                  <% end %>
                                <% end %>

                                <.icon
                                  :if={@can_manage?}
                                  name="bilimbi-pencil"
                                  class="size-3 text-ink-subtle ml-0.5"
                                />
                              </div>
                            <% end %>
                          </td>

                          <td class="py-2 px-3">
                            <%= if @can_manage? do %>
                              <button
                                id={"toggle-primary-#{addr.id}"}
                                type="button"
                                phx-click="toggle_address_primary"
                                phx-value-id={addr.id}
                                class="cursor-pointer"
                                title="Toggle primary status"
                              >
                                <%= if addr.is_primary do %>
                                  <.badge kind={:success}>Yes</.badge>
                                <% else %>
                                  <span class="text-ink-subtle hover:text-ink">No</span>
                                <% end %>
                              </button>
                            <% else %>
                              <%= if addr.is_primary do %>
                                <.badge kind={:success}>Yes</.badge>
                              <% else %>
                                <span class="text-ink-subtle">No</span>
                              <% end %>
                            <% end %>
                          </td>

                          <td class="py-2 px-3 tabular-nums">
                            <%= if @editing_priority_address_id == addr.id do %>
                              <form
                                phx-submit="save_address_priority"
                                id={"priority-form-#{addr.id}"}
                                class="flex items-center gap-1"
                              >
                                <input type="hidden" name="address_id" value={addr.id} />
                                <input
                                  type="number"
                                  name="priority"
                                  id={"input-priority-#{addr.id}"}
                                  value={@edit_priority_value}
                                  min="0"
                                  class="w-14 rounded border border-line bg-surface px-1.5 py-0.5 text-xs text-ink"
                                />
                                <.button type="submit" variant="primary" class="text-xs px-2 py-0.5">✓</.button>
                                <.button
                                  type="button"
                                  phx-click="cancel_address_priority"
                                  class="text-xs px-2 py-0.5"
                                >✕</.button>
                              </form>
                            <% else %>
                              <div
                                phx-click={if @can_manage?, do: "edit_address_priority"}
                                phx-value-id={addr.id}
                                class={[
                                  "inline-flex items-center gap-1",
                                  @can_manage? && "cursor-pointer hover:opacity-80"
                                ]}
                              >
                                <span>{addr.priority || 0}</span>
                                <.icon
                                  :if={@can_manage?}
                                  name="bilimbi-pencil"
                                  class="size-3 text-ink-subtle"
                                />
                              </div>
                            <% end %>
                          </td>

                          <td class="py-2 px-3 tabular-nums text-ink-subtle">
                            {display_or_dash(addr.valid_from)}
                          </td>

                          <td class="py-2 px-3 tabular-nums text-ink-subtle">
                            {display_or_dash(addr.valid_to)}
                          </td>

                          <td :if={@can_manage?} class="py-2 pl-3 text-right">
                            <.button
                              id={"unlink-address-#{addr.id}"}
                              type="button"
                              phx-click="detach_address"
                              phx-value-id={addr.id}
                              data-confirm="Are you sure you want to unlink this address?"
                              class="text-danger hover:bg-danger/10 text-xs px-2 py-1"
                            >
                              <.icon name="bilimbi-link-slash" class="size-3.5" />
                              <span class="sr-only">Unlink</span>
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
        <!-- Attach Address Modal Dialog -->
        <div
          :if={@show_attach_modal}
          id="attach-address-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-2xl border border-line bg-surface p-6 shadow-lg space-y-4">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              Attach Address
            </h3>

            <p class="text-xs text-ink-muted">
              Select an address from the company to attach to this employee.
            </p>

            <.form
              for={@attach_form}
              phx-submit="attach_address"
              id="attach-address-modal-form"
              class="space-y-4"
            >
              <div>
                <label
                  for="employee-attach-address"
                  class="block text-xs font-semibold text-ink-subtle uppercase tracking-wider mb-1"
                >
                  Address
                </label>

                <select
                  id="employee-attach-address"
                  name="address[address_id]"
                  class="w-full rounded-lg border border-line bg-surface px-3 py-2 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                >
                  <option value="">Select an address...</option>

                  <%= for addr <- @available_addresses do %>
                    <option value={addr.id}>
                      {addr.label} — {format_address_summary(addr)}
                    </option>
                  <% end %>
                </select>

                <%= if Map.has_key?(@attach_errors, :address_id) do %>
                  <p class="text-xs text-danger mt-1">{@attach_errors.address_id}</p>
                <% end %>
              </div>

              <div>
                <span class="block text-xs font-semibold text-ink-subtle uppercase tracking-wider mb-1">
                  Kind
                </span>

                <div class="flex flex-wrap gap-x-4 gap-y-2">
                  <%= for k <- @address_kinds do %>
                    <label class="flex items-center gap-2 text-xs text-ink cursor-pointer">
                      <input
                        id={"employee-attach-kind-#{k}"}
                        type="checkbox"
                        name="address[kinds][]"
                        value={k}
                        class="rounded border-line"
                      /> <span>{String.capitalize(k)}</span>
                    </label>
                  <% end %>
                </div>
              </div>

              <div class="flex items-center gap-2">
                <input
                  id="employee-attach-is-primary"
                  type="checkbox"
                  name="address[is_primary]"
                  value="true"
                  class="rounded border-line"
                />
                <label
                  for="employee-attach-is-primary"
                  class="text-xs font-medium text-ink cursor-pointer"
                >
                  Primary Address
                </label>
              </div>

              <div>
                <label
                  for="employee-attach-priority"
                  class="block text-xs font-semibold text-ink-subtle uppercase tracking-wider mb-1"
                >
                  Priority
                </label>

                <input
                  id="employee-attach-priority"
                  type="number"
                  name="address[priority]"
                  value="0"
                  min="0"
                  class="w-24 rounded-lg border border-line bg-surface px-3 py-2 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                />
                <p class="text-xs text-ink-subtle mt-1">
                  Lower number = higher priority. Used to order addresses of the same kind (0 = top).
                </p>
              </div>

              <div class="flex items-center justify-end gap-2 pt-2 border-t border-line">
                <.button type="button" phx-click="close_attach_modal" class="text-xs px-3 py-1.5">
                  Cancel
                </.button>

                <.button
                  id="btn-submit-attach-address"
                  type="submit"
                  variant="primary"
                  class="text-xs px-3 py-1.5"
                >
                  Attach
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </.page>
    </Layouts.app>
    """
  end

  defp format_address_summary(addr) do
    [addr.line1, addr.locality, addr.country_iso]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("probation"), do: :warning
  defp status_badge_kind("terminated"), do: :danger
  defp status_badge_kind(_), do: :neutral

  defp display_or_dash(nil), do: "—"
  defp display_or_dash(""), do: "—"
  defp display_or_dash(value), do: to_string(value)

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
