defmodule Bilimbi.Core.User.Web.ShowLive do
  @moduledoc """
  Read-first LiveView adapter for one tenant-visible user.

  The page shows the account as facts. An operator holding `admin.user.update`
  edits each fact in place and a committed edit saves by itself; there is no
  edit mode and no "Edit user" button, as on `/addresses/:id`:

  - the name and email commit on Enter or on leaving the field, through
    `<.inline_edit>`; Escape cancels. Neither column is nullable, so an
    emptied value commits nothing;
  - the company is a choice fact: it reads as the company name and becomes
    a select on click; the select commits on change, and Escape or leaving
    it cancels, as Belimbing's `admin/users/show` edit-in-place select does.
    The select offers this workspace's live companies and nothing else: a
    user always belongs to a company, and is the same person operating
    under a different one, so there is no blank option and no way to detach
    an account here. Belimbing offers "None" on that select; Bilimbi does
    not, because `User.get_tenant_user/2` resolves a user through its
    company and no screen could reopen a detached account. A blank value
    that still arrives is refused on the fact and writes nothing.
    `reassign_user_company/6` ends every session the account holds, so the
    open editor says so before the operator chooses; the warning is a note
    beside the select, not a second click, because the change is reversible
    by choosing the previous company again.

  Every account this page mounts has a company — `get_tenant_user/2`
  returns no other — so every fact has a company for Core User to write it
  through. When that company is archived, `Company.list_companies/1` does not
  name it and the page reads it as an archived company rather than as no
  company at all.

  Each fact reports its own outcome through the shared commit status that
  `Bilimbi.Base.UI.CommitStatus` keeps: "Saving…" while the round trip is in
  flight, "Saved" once stored, and an alert on the fact naming the rejected
  value and the validation error when the save was refused. The stored value
  stays on screen until the server confirms a change, and success does not
  flash.

  The header presents the same quiet labelled row Belimbing does — History,
  Impersonate and "← Back", each with its glyph and its word — and no button.
  Impersonate keeps its guards unchanged: `admin.user.impersonate`, never the
  signed-in account, and never while already impersonating.

  Roles and capability assignments, password updates, employee
  linking/creation and the external accesses read model keep their own
  sections and their own affordances.
  """

  use Bilimbi.Base.UI, :live_view

  # These four toggles only flip section-visibility assigns; every
  # persisting event behind them (`assign_roles`, password change, employee
  # link) carries its own capability check (#420).
  @write_guard_opt_out ~w(toggle_assign_roles toggle_change_password
                          toggle_effective_permissions toggle_link_employee)

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.CommitStatus

  @manage_capability "admin.user.update"
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    with {user_id, ""} <- Integer.parse(id),
         {:ok, user} <- User.get_tenant_user(scope, user_id) do
      socket =
        socket
        |> assign(:active_nav, "admin.user")
        |> assign(:user_id, user_id)
        |> init_ui_state()
        |> load_data(user)

      {:ok, socket}
    else
      _ -> {:ok, not_found(socket)}
    end
  end

  # The facts an inline text edit may write, keyed by the form name the hook
  # pushes. A name outside this map is ignored; user input never becomes an
  # atom. `company` is the choice fact and has its own event.
  @inline_fields %{"name" => :name, "email" => :email}

  @fact_labels %{"name" => "Name", "email" => "Email", "company" => "Company"}

  defp init_ui_state(socket) do
    socket
    |> CommitStatus.init()
    |> assign(:editing_field, nil)
    |> assign(:show_assign_roles, false)
    |> assign(:role_search, "")
    |> assign(:selected_role_ids, [])
    |> assign(:show_effective_permissions, false)
    |> assign(:capability_search, "")
    |> assign(:selected_capability_keys, [])
    |> assign(:show_change_password, false)
    |> assign(:password_form, to_form(%{"password" => "", "password_confirmation" => ""}))
    |> assign(:password_errors, %{})
    |> assign(:show_add_employee_modal, false)
    |> assign(
      :new_employee_form,
      to_form(%{
        "company_id" => nil,
        "employee_number" => "",
        "full_name" => "",
        "designation" => "",
        "employment_start" => ""
      })
    )
    |> assign(:new_employee_errors, %{})
    |> assign(:show_link_employee, false)
    |> assign(:employees_sort_by, "employee_number")
    |> assign(:employees_sort_dir, "asc")
    |> assign(:external_accesses_sort_by, "company")
    |> assign(:external_accesses_sort_dir, "asc")
  end

  defp load_data(socket, user) do
    scope = socket.assigns.current_scope.scope
    current_scope = socket.assigns.current_scope
    can_manage? = allowed?(current_scope, @manage_capability)

    {:ok, companies} = Company.list_companies(scope)
    company_names = Map.new(companies, &{&1.id, Company.Summary.display_name(&1)})

    # Assigned roles
    role_page = Authz.list_principal_role_assignments(scope, :user, user.id, page_size: 100)
    assigned_roles = role_page.entries
    assigned_role_ids = Enum.map(assigned_roles, & &1.role_id)
    has_grant_all? = Enum.any?(assigned_roles, & &1.role_grant_all)

    # Acting administrator permissions for privilege escalation prevention (#352)
    acting_grant_all? = acting_grant_all?(current_scope)
    acting_allowed_caps = acting_allowed_capabilities(current_scope)
    acting_allowed_set = MapSet.new(acting_allowed_caps)

    # Available roles for assignment (restricted to roles grantable by the acting administrator)
    all_roles = Authz.list_roles(scope)
    unassigned_roles = Enum.reject(all_roles, &(&1.id in assigned_role_ids))

    available_roles =
      Enum.filter(unassigned_roles, fn role ->
        role_grantable?(scope, role.id, acting_grant_all?, acting_allowed_set)
      end)

    # Direct principal capabilities
    direct_caps_page =
      Authz.list_principal_capabilities(scope,
        principal_type: :user,
        principal_id: user.id,
        page_size: 100
      )

    direct_grant_ids =
      direct_caps_page.entries
      |> Enum.filter(& &1.allowed)
      |> Map.new(&{&1.capability, &1.id})

    direct_deny_ids =
      direct_caps_page.entries
      |> Enum.reject(& &1.allowed)
      |> Map.new(&{&1.capability, &1.id})

    # Effective permissions
    {effective_keys, grouped_effective_permissions} =
      if is_nil(user.company_id) do
        {[], %{}}
      else
        actor = Authz.actor(:user, user.id, scope, user.company_id)
        effective = Authz.effective_capabilities(actor)
        allowed_caps = Enum.sort(effective.allowed)
        {allowed_caps, group_by_domain(allowed_caps)}
      end

    # Grouped denied permissions
    denied_keys = Map.keys(direct_deny_ids) |> Enum.sort()
    grouped_denied_permissions = group_by_domain(denied_keys)

    # Available capabilities (all registry capabilities minus effective minus denied,
    # restricted to capabilities held by the acting administrator)
    excluded_keys = MapSet.new(effective_keys ++ denied_keys)
    all_registered_caps = Authz.capabilities() |> Enum.sort()

    available_caps =
      all_registered_caps
      |> Enum.reject(&MapSet.member?(excluded_keys, &1))
      |> then(fn caps ->
        if acting_grant_all? do
          caps
        else
          Enum.filter(caps, &MapSet.member?(acting_allowed_set, &1))
        end
      end)

    grouped_available_capabilities = group_by_domain(available_caps)

    # Employees
    linked_employees =
      case user.employee_id do
        nil ->
          []

        emp_id ->
          case Employee.get_employee(scope, emp_id) do
            {:ok, emp} -> [emp]
            _ -> []
          end
      end

    # Unlinkable employees (tenant employees not linked to any user in the tenant)
    tenant_employees =
      Enum.flat_map(companies, fn company ->
        case Employee.list_employees(scope, company.id) do
          {:ok, emps} -> emps
          _ -> []
        end
      end)

    unlinkable_employees =
      if is_nil(user.company_id) do
        []
      else
        # filter to company employees not already linked to this user
        tenant_employees
        |> Enum.filter(&(&1.company_id == user.company_id and &1.id != user.employee_id))
        |> Enum.sort_by(& &1.full_name)
      end

    # External accesses
    {:ok, external_accesses} = Company.list_external_accesses_for_user(scope, user.id)

    relevant_company_ids =
      [user.company_id | Enum.map(linked_employees, & &1.company_id)]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    department_names =
      relevant_company_ids
      |> Enum.flat_map(fn comp_id ->
        case Company.list_departments(scope, comp_id) do
          {:ok, depts} ->
            Enum.flat_map(depts, fn dept ->
              case dept.type do
                %{name: name} when is_binary(name) and name != "" -> [{dept.id, name}]
                _ -> []
              end
            end)

          {:error, _} ->
            []
        end
      end)
      |> Map.new()

    socket
    |> assign(:user, user)
    |> assign(:page_title, user.name)
    |> assign(:can_manage?, can_manage?)
    |> assign(:companies, companies)
    |> assign(:company_names, company_names)
    |> assign(:company_name, Map.get(company_names, user.company_id))
    |> assign(:department_names, department_names)
    |> assign(:assigned_roles, assigned_roles)
    |> assign(:assigned_role_ids, assigned_role_ids)
    |> assign(:has_grant_all?, has_grant_all?)
    |> assign(:available_roles, available_roles)
    |> assign(
      :filtered_available_roles,
      filter_roles(available_roles, socket.assigns[:role_search] || "")
    )
    |> assign(:direct_grant_ids, direct_grant_ids)
    |> assign(:direct_deny_ids, direct_deny_ids)
    |> assign(:effective_keys, effective_keys)
    |> assign(:grouped_effective_permissions, grouped_effective_permissions)
    |> assign(:grouped_denied_permissions, grouped_denied_permissions)
    |> assign(:grouped_available_capabilities, grouped_available_capabilities)
    |> assign(:employees, linked_employees)
    |> assign(
      :sorted_employees,
      sort_employees(
        linked_employees,
        socket.assigns[:employees_sort_by] || "employee_number",
        socket.assigns[:employees_sort_dir] || "asc",
        company_names,
        department_names
      )
    )
    |> assign(:unlinkable_employees, unlinkable_employees)
    |> assign(:external_accesses, external_accesses)
    |> assign(
      :sorted_external_accesses,
      sort_external_accesses(
        external_accesses,
        socket.assigns[:external_accesses_sort_by] || "company",
        socket.assigns[:external_accesses_sort_dir] || "asc",
        company_names
      )
    )
  end

  defp user_auditable_types,
    do: ["Bilimbi.Core.User.Schema", User.notifiable_identity()]

  # --- Event Handlers: In-place Facts ---

  # One commit, one outcome on the fact that made it. Every write re-asks
  # Authz; the `can_manage?` assign only decides what the page shows.
  @impl true
  def handle_event("save_field", params, socket) do
    if can_manage?(socket) do
      case CommitStatus.inline_field(params, @inline_fields) do
        {:ok, name, field, value} ->
          {:noreply, save_fact(socket, name, %{field => value}, value)}

        :error ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("edit_field", %{"field" => "company"}, socket) do
    if can_manage?(socket) do
      {:noreply, assign(socket, :editing_field, "company")}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("edit_field", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit_field", _params, socket) do
    {:noreply, close_company_editor(socket)}
  end

  # The company choice commits on change, as Belimbing's saveCompany does.
  # Only a reassignment is offered: the select carries no blank option, so a
  # blank value is a forged or stale submission and is refused on the fact
  # without a write. The reassignment ends the account's sessions; the open
  # editor warned about that before the choice was made.
  def handle_event("save_company", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user
      current_company_id = user.company_id

      case chosen_company_id(params) do
        nil ->
          {:noreply,
           socket
           |> close_company_editor()
           |> CommitStatus.put("company", {:error, detach_refused_message()})}

        ^current_company_id ->
          {:noreply, commit_company(socket, {:ok, user}, socket.assigns.company_name)}

        target_company_id ->
          actor = current_actor(socket, user.company_id)

          {:noreply,
           commit_company(
             socket,
             User.reassign_user_company(
               actor,
               scope,
               user.company_id,
               user.id,
               target_company_id
             ),
             company_choice_label(socket, target_company_id)
           )}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # --- Event Handlers: Roles ---

  def handle_event("toggle_assign_roles", _params, socket) do
    {:noreply, assign(socket, :show_assign_roles, not socket.assigns.show_assign_roles)}
  end

  def handle_event("search_roles", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:role_search, query)
     |> assign(:filtered_available_roles, filter_roles(socket.assigns.available_roles, query))}
  end

  def handle_event("select_roles", params, socket) do
    role_ids = Map.get(params, "role_ids", [])
    {:noreply, assign(socket, :selected_role_ids, role_ids)}
  end

  def handle_event("assign_selected_roles", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user
      current_scope = socket.assigns.current_scope

      role_ids =
        case Map.get(params, "role_ids") do
          ids when is_list(ids) and ids != [] -> ids
          _ -> socket.assigns.selected_role_ids
        end

      parsed_role_ids =
        for role_id_str <- role_ids,
            {role_id, ""} <- [Integer.parse(to_string(role_id_str))] do
          role_id
        end

      acting_grant_all? = acting_grant_all?(current_scope)
      acting_allowed_caps = acting_allowed_capabilities(current_scope)
      acting_allowed_set = MapSet.new(acting_allowed_caps)

      unauthorized_roles =
        Enum.reject(
          parsed_role_ids,
          &role_grantable?(scope, &1, acting_grant_all?, acting_allowed_set)
        )

      cond do
        user.company_id == nil ->
          {:noreply, socket}

        unauthorized_roles != [] ->
          {:noreply, put_flash(socket, :error, "You cannot grant roles you do not hold.")}

        parsed_role_ids != [] ->
          for role_id <- parsed_role_ids do
            Authz.assign_role(scope, user.company_id, :user, user.id, role_id)
          end

          count = length(parsed_role_ids)
          msg = if count == 1, do: "Assigned 1 role.", else: "Assigned #{count} roles."

          {:noreply,
           socket
           |> put_flash(:info, msg)
           |> assign(:selected_role_ids, [])
           |> assign(:show_assign_roles, false)
           |> load_data(user)}

        true ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage roles.")}
    end
  end

  def handle_event(
        "remove_role",
        %{"assignment-id" => assignment_id_str, "role-id" => role_id_str},
        socket
      ) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      with {assignment_id, ""} <- Integer.parse(assignment_id_str),
           {role_id, ""} <- Integer.parse(role_id_str) do
        case Authz.unassign_role(scope, role_id, assignment_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Role removed.")
             |> load_data(user)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove role.")}
        end
      else
        _ -> {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage roles.")}
    end
  end

  # --- Event Handlers: Permissions ---

  def handle_event("toggle_effective_permissions", _params, socket) do
    {:noreply,
     assign(socket, :show_effective_permissions, not socket.assigns.show_effective_permissions)}
  end

  def handle_event("search_capabilities", %{"value" => query}, socket) do
    {:noreply, assign(socket, :capability_search, query)}
  end

  def handle_event("select_capabilities", params, socket) do
    cap_keys = Map.get(params, "capability_keys", [])
    {:noreply, assign(socket, :selected_capability_keys, cap_keys)}
  end

  def handle_event("add_selected_capabilities", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user
      current_scope = socket.assigns.current_scope

      cap_keys =
        case Map.get(params, "capability_keys") do
          keys when is_list(keys) and keys != [] -> keys
          _ -> socket.assigns.selected_capability_keys
        end

      acting_grant_all? = acting_grant_all?(current_scope)
      acting_allowed_caps = acting_allowed_capabilities(current_scope)
      acting_allowed_set = MapSet.new(acting_allowed_caps)

      unauthorized_caps =
        if acting_grant_all? do
          []
        else
          Enum.reject(cap_keys, &MapSet.member?(acting_allowed_set, &1))
        end

      cond do
        user.company_id == nil ->
          {:noreply, socket}

        unauthorized_caps != [] ->
          {:noreply, put_flash(socket, :error, "You cannot grant capabilities you do not hold.")}

        cap_keys != [] ->
          for cap_key <- cap_keys do
            Authz.put_principal_capability(scope, user.company_id, :user, user.id, cap_key, true)
          end

          count = length(cap_keys)
          msg = if count == 1, do: "Granted 1 capability.", else: "Granted #{count} capabilities."

          {:noreply,
           socket
           |> put_flash(:info, msg)
           |> assign(:selected_capability_keys, [])
           |> load_data(user)}

        true ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage capabilities.")}
    end
  end

  def handle_event("deny_capability", %{"capability-key" => cap_key}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      if user.company_id do
        case Authz.put_principal_capability(
               scope,
               user.company_id,
               :user,
               user.id,
               cap_key,
               false
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Capability #{cap_key} denied.")
             |> load_data(user)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to deny capability.")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage capabilities.")}
    end
  end

  def handle_event("remove_capability", %{"grant-id" => grant_id_str}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      case Integer.parse(grant_id_str) do
        {grant_id, ""} ->
          case Authz.remove_principal_capability(scope, grant_id) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, "Capability rule removed.")
               |> load_data(user)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to remove capability rule.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage capabilities.")}
    end
  end

  # --- Event Handlers: Password ---

  def handle_event("toggle_change_password", _params, socket) do
    {:noreply, assign(socket, :show_change_password, not socket.assigns.show_change_password)}
  end

  def handle_event("update_password", params, socket) do
    if can_manage?(socket) do
      p = params["user"] || params
      password = p["password"] || ""
      confirmation = p["password_confirmation"] || ""
      errors = validate_password_params(password, confirmation)

      if errors == %{} do
        scope = socket.assigns.current_scope.scope
        user = socket.assigns.user
        actor = current_actor(socket, user.company_id)

        case User.admin_change_password(actor, scope, user.company_id, user.id, password) do
          {:ok, updated_user} ->
            {:noreply,
             socket
             |> put_flash(:info, "Password updated successfully.")
             |> assign(
               :password_form,
               to_form(%{"password" => "", "password_confirmation" => ""})
             )
             |> assign(:password_errors, %{})
             |> assign(:show_change_password, false)
             |> load_data(updated_user)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to update password.")}
        end
      else
        {:noreply,
         socket
         |> assign(:password_errors, errors)
         |> put_flash(
           :error,
           Map.get(errors, :password_confirmation) || Map.get(errors, :password) ||
             "Invalid password."
         )
         |> assign(
           :password_form,
           to_form(%{"password" => password, "password_confirmation" => confirmation})
         )}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to change passwords.")}
    end
  end

  # --- Event Handlers: Employee Records ---

  def handle_event("toggle_link_employee", _params, socket) do
    {:noreply, assign(socket, :show_link_employee, not socket.assigns.show_link_employee)}
  end

  def handle_event("link_employee", %{"employee_id" => employee_id_str}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      case Integer.parse(employee_id_str) do
        {employee_id, ""} ->
          case User.update_user(scope, user.company_id, user.id, %{employee_id: employee_id}) do
            {:ok, updated_user} ->
              {:noreply,
               socket
               |> put_flash(:info, "Employee linked.")
               |> assign(:show_link_employee, false)
               |> load_data(updated_user)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to link employee.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit users.")}
    end
  end

  def handle_event("unlink_employee", %{"employee-id" => _employee_id_str}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      case User.update_user(scope, user.company_id, user.id, %{employee_id: nil}) do
        {:ok, updated_user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Employee unlinked.")
           |> load_data(updated_user)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to unlink employee.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit users.")}
    end
  end

  def handle_event("open_add_employee_modal", _params, socket) do
    user = socket.assigns.user

    {:noreply,
     socket
     |> clear_flash()
     |> assign(:show_add_employee_modal, true)
     |> assign(
       :new_employee_form,
       to_form(%{
         "company_id" => user.company_id,
         "employee_number" => "",
         "full_name" => "",
         "designation" => "",
         "employment_start" => ""
       })
     )
     |> assign(:new_employee_errors, %{})}
  end

  def handle_event("close_add_employee_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_employee_modal, false)}
  end

  def handle_event("save_new_employee", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user
      p = params["employee"] || params

      company_id =
        case Integer.parse(to_string(p["company_id"] || "")) do
          {cid, ""} -> cid
          _ -> user.company_id
        end

      emp_number = String.trim(to_string(p["employee_number"] || ""))
      full_name = String.trim(to_string(p["full_name"] || ""))
      designation = String.trim(to_string(p["designation"] || ""))
      employment_start = p["employment_start"]

      errors = %{}

      errors =
        if emp_number == "", do: Map.put(errors, :employee_number, "can't be blank"), else: errors

      errors = if full_name == "", do: Map.put(errors, :full_name, "can't be blank"), else: errors

      errors =
        if is_nil(company_id), do: Map.put(errors, :company_id, "can't be blank"), else: errors

      if errors == %{} do
        attrs = %{
          employee_number: emp_number,
          full_name: full_name,
          designation: if(designation == "", do: nil, else: designation),
          employee_type: "full_time",
          status: "active",
          employment_start:
            if(employment_start in ["", nil], do: nil, else: Date.from_iso8601!(employment_start))
        }

        with {:ok, employee} <- Employee.create_employee(scope, company_id, attrs),
             {:ok, updated_user} <-
               User.update_user(scope, user.company_id, user.id, %{employee_id: employee.id}) do
          {:noreply,
           socket
           |> put_flash(:info, "Employee created and linked.")
           |> assign(:show_add_employee_modal, false)
           |> load_data(updated_user)}
        else
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create employee record.")}
        end
      else
        {:noreply,
         socket
         |> assign(:new_employee_errors, errors)
         |> assign(:new_employee_form, to_form(params))}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit users.")}
    end
  end

  # --- Event Handlers: Table Sorting ---

  def handle_event("sort_employees", params, socket) do
    sort_col = params["sort"] || params["sort_by"] || "employee_number"
    current_dir = socket.assigns.employees_sort_dir
    current_col = socket.assigns.employees_sort_by

    new_dir =
      if current_col == sort_col and current_dir == "asc" do
        "desc"
      else
        "asc"
      end

    sorted =
      sort_employees(
        socket.assigns.employees,
        sort_col,
        new_dir,
        socket.assigns.company_names,
        socket.assigns.department_names
      )

    {:noreply,
     socket
     |> assign(:employees_sort_by, sort_col)
     |> assign(:employees_sort_dir, new_dir)
     |> assign(:sorted_employees, sorted)}
  end

  def handle_event("sort_external_accesses", params, socket) do
    sort_col = params["sort"] || params["sort_by"] || "company"
    current_dir = socket.assigns.external_accesses_sort_dir
    current_col = socket.assigns.external_accesses_sort_by

    new_dir =
      if current_col == sort_col and current_dir == "asc" do
        "desc"
      else
        "asc"
      end

    sorted =
      sort_external_accesses(
        socket.assigns.external_accesses,
        sort_col,
        new_dir,
        socket.assigns.company_names
      )

    {:noreply,
     socket
     |> assign(:external_accesses_sort_by, sort_col)
     |> assign(:external_accesses_sort_dir, new_dir)
     |> assign(:sorted_external_accesses, sorted)}
  end

  # --- Event Handlers: Deletion ---

  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user

    cond do
      user.id == socket.assigns.current_scope.user["user_id"] ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}

      not allowed?(socket.assigns.current_scope, "admin.user.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete users.")}

      true ->
        case User.delete_user(scope, user.company_id, user.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "User deleted successfully.")
             |> push_navigate(to: ~p"/users")}

          {:error, :company_not_found} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "That user cannot be deleted while their company is archived."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "That user could not be deleted.")}
        end
    end
  end

  # --- Render Template ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          {@user.name}
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin this user to sidebar"
              context={:inline}
              id="user-pin"
              data-nav-pin="record"
              data-nav-pin-record="true"
              data-nav-pin-label={"Administration / Users / #{@user.name}"}
              data-nav-pin-url={~p"/users/#{@user.id}"}
              aria-pressed="false"
              />
          </:title_actions>
          <:subtitle>
            <%= if @company_name do %>
              {@company_name}
            <% else %>
              Archived company
            <% end %>
          </:subtitle>
          <:actions>
            <%!-- Belimbing's admin/users/show header: History, Impersonate
                 and Back as one quiet labelled row, each glyph beside its
                 word, and no button. The row wraps at narrow widths instead
                 of clipping. --%>
            <div class="flex flex-wrap items-center gap-3">
              <.discovered_panel
                key="record.history"
                id="user-record-history"
                current_scope={@current_scope}
                opts={%{auditable_types: user_auditable_types(), auditable_id: @user.id}}
              />
              <.action_link
                :if={can_impersonate?(@current_scope, @user)}
                id="user-impersonate"
                icon="bilimbi-impersonate"
                href={~p"/admin/impersonate/#{@user.id}"}
                method="post"
                title="Impersonate this user"
              >
                Impersonate
              </.action_link>
              <.back_link id="user-back" navigate={~p"/users"} title="Back to users" />
            </div>
          </:actions>
        </.header>

        <div class="mt-6 space-y-6">
          <!-- Card 1: User Details, read-first -->
          <.card id="user-details-card" inner_class="p-5 sm:p-6">
            <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-4">
              User Details
            </h3>

            <dl class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <.text_fact
                name="name"
                user={@user}
                can_manage?={@can_manage?}
                field_status={@field_status}
              />
              <.text_fact
                name="email"
                user={@user}
                can_manage?={@can_manage?}
                field_status={@field_status}
              />

              <div id="user-detail-company">
                <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                  Company
                </dt>
                <dd id="user-view-company" class="mt-0.5 text-sm text-ink">
                  <button
                    :if={@can_manage? and @editing_field != "company"}
                    type="button"
                    id="user-company-display"
                    phx-click="edit_field"
                    phx-value-field="company"
                    aria-label="Edit company"
                    aria-describedby={@field_status["company"] && "user-company-status"}
                    class="group -mx-1.5 flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 text-left transition-colors hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
                  >
                    <span :if={@company_name} class="text-ink">{@company_name}</span>
                    <span :if={is_nil(@company_name)} class="text-ink-muted">Archived company</span>
                    <.icon
                      name="edit"
                      class="size-3.5 shrink-0 text-ink-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
                    />
                  </button>

                  <%!-- Window-scoped: the select may not hold focus (JS.focus is
                       best-effort), and Escape must cancel regardless. Only one
                       editor mounts at a time, so the listener is unambiguous. --%>
                  <div
                    :if={@can_manage? and @editing_field == "company"}
                    phx-window-keydown="cancel_edit_field"
                    phx-key="Escape"
                  >
                    <form id="user-company-form" phx-change="save_company" class="inline-block">
                      <select
                        id="user-company-select"
                        name="company_id"
                        aria-label="Company"
                        aria-describedby="user-company-warning"
                        phx-mounted={JS.focus()}
                        phx-blur="cancel_edit_field"
                        class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                      >
                        <option
                          :for={company <- @companies}
                          value={company.id}
                          selected={@user.company_id == company.id}
                        >
                          {Company.Summary.display_name(company)}
                        </option>
                      </select>
                    </form>

                    <%!-- The choice commits on change and the write ends the
                         account's sessions, so the warning stands before the
                         choice, beside the select, where the operator reads it
                         first; it is a note, not a second click. --%>
                    <p id="user-company-warning" class="mt-1 text-xs text-warning-ink">
                      Changing the company signs {@user.name} out of every session.
                    </p>
                  </div>

                  <%= if not @can_manage? do %>
                    <%= if @company_name do %>
                      <.link
                        navigate={~p"/companies/#{@user.company_id}"}
                        class="text-action hover:underline"
                      >
                        {@company_name}
                      </.link>
                    <% else %>
                      <span class="text-ink-muted">Archived company</span>
                    <% end %>
                  <% end %>

                  <.commit_status id="user-company-status" status={@field_status["company"]} />
                </dd>
              </div>

              <div id="user-detail-email-verified">
                <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                  Email Verified
                </dt>
                <dd class="mt-0.5 text-sm text-ink">
                  <.badge kind={if @user.email_verified_at, do: :success, else: :warning}>
                    <%= if @user.email_verified_at do %>
                      <.datetime id="user-email-verified-at" value={@user.email_verified_at} />
                    <% else %>
                      unverified
                    <% end %>
                  </.badge>
                </dd>
              </div>

              <div id="user-detail-created">
                <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                  Created
                </dt>
                <dd class="mt-0.5 text-sm text-ink-muted tabular-nums">
                  <.datetime :if={@user.created_at} id="user-created-at" value={@user.created_at} />
                  <span :if={is_nil(@user.created_at)} class="text-ink-faint">—</span>
                </dd>
              </div>

              <div id="user-detail-updated">
                <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                  Updated
                </dt>
                <dd class="mt-0.5 text-sm text-ink-muted tabular-nums">
                  <.datetime :if={@user.updated_at} id="user-updated-at" value={@user.updated_at} />
                  <span :if={is_nil(@user.updated_at)} class="text-ink-faint">—</span>
                </dd>
              </div>
            </dl>
          </.card>

          <!-- Card 2: Roles & Permissions -->
          <.card id="user-roles-card" inner_class="p-5 sm:p-6 space-y-4">
            <div class="flex items-center justify-between mb-1">
              <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                Roles & Permissions
                <span
                  id="assigned-roles-count"
                  class="ml-1.5 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink"
                >
                  {length(@assigned_roles)}
                </span>
              </h3>
            </div>
            <p class="max-w-prose text-xs text-ink-muted mt-0.5 mb-4">
              Roles determine what this user can do. Each role grants a set of capabilities. Effective permissions show the combined result of all assigned roles.
            </p>

            <%= if is_nil(@user.company_id) do %>
              <.alert kind={:info} id="roles-unaffiliated-alert" class="mb-4">
                Assign a company in User Details before roles or capabilities can be managed. Permissions are evaluated in a company scope.
              </.alert>
            <% end %>

            <!-- Assigned Roles -->
            <dl class="mb-4" id="assigned-roles-container">
              <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-2">
                Roles
              </dt>
              <dd>
                <%= if @assigned_roles == [] do %>
                  <span class="text-sm text-ink-muted" id="no-roles-msg">No roles assigned.</span>
                <% else %>
                  <div class="flex flex-wrap gap-2" id="assigned-roles-list">
                    <span
                      :for={assignment <- @assigned_roles}
                      id={"assigned-role-#{assignment.id}"}
                      class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink"
                    >
                      <span>{assignment.role_name}</span>
                      <.icon_button
                        :if={@can_manage?}
                        icon="close"
                        label={"Remove the #{assignment.role_name} role"}
                        context={:inline}
                        kind={:danger}
                        id={"remove-role-#{assignment.id}"}
                        phx-click="remove_role"
                        phx-value-assignment-id={assignment.id}
                        phx-value-role-id={assignment.role_id}
                        data-confirm={
                          "Remove the #{assignment.role_name} role from #{@user.name}? " <>
                            "They lose every capability this role grants, unless another " <>
                            "role or direct grant also provides it."
                        }
                        class="-mr-1"
                      />
                    </span>
                  </div>
                <% end %>
              </dd>
            </dl>

            <!-- Assign Roles Form (Expandable) -->
            <%= if @can_manage? and not is_nil(@user.company_id) and @available_roles != [] and not @has_grant_all? do %>
              <div class="mb-6">
                <div :if={not @show_assign_roles}>
                  <.button
                    type="button"
                    id="toggle-assign-roles-btn"
                    phx-click="toggle_assign_roles"
                    class="text-xs font-medium"
                  >
                    <.icon name="create" class="size-3.5" />
                    <span>Roles</span>
                  </.button>
                </div>
                <div
                  :if={@show_assign_roles}
                  id="assign-roles-picker"
                  class="rounded-xl border border-line bg-surface p-3 space-y-3 shadow-xs"
                >
                  <div>
                    <input
                      type="text"
                      id="role-search-input"
                      phx-input="search_roles"
                      placeholder="Search roles..."
                      value={@role_search}
                      class="w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none"
                    />
                  </div>
                  <form
                    phx-change="select_roles"
                    phx-submit="assign_selected_roles"
                    id="assign-roles-form"
                  >
                    <div
                      class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-1 max-h-48 overflow-y-auto"
                      id="available-roles-list"
                    >
                      <label
                        :for={role <- @filtered_available_roles}
                        id={"available-role-label-#{role.id}"}
                        class="flex items-center gap-2 px-2 py-1 rounded text-sm hover:bg-surface-sunken cursor-pointer text-ink"
                      >
                        <input
                          type="checkbox"
                          name="role_ids[]"
                          value={role.id}
                          checked={to_string(role.id) in @selected_role_ids}
                          class="rounded border-high-contrast-line accent-action focus:ring-brand-strong/30"
                        />
                        <span class="truncate" title={role.name}>{role.name}</span>
                      </label>
                    </div>
                    <div class="flex items-center gap-2 mt-2">
                      <.button
                        :if={@selected_role_ids != []}
                        type="submit"
                        variant="primary"
                        id="confirm-assign-roles-btn"
                        class="text-xs"
                      >
                        Assign ({length(@selected_role_ids)})
                      </.button>
                      <.button
                        type="button"
                        phx-click="toggle_assign_roles"
                        class="text-xs"
                      >
                        Cancel
                      </.button>
                    </div>
                  </form>
                </div>
              </div>
            <% end %>

            <!-- Effective Permissions Disclosure -->
            <div id="effective-permissions-section" class="border-t border-line pt-4">
              <button
                type="button"
                id="toggle-permissions-btn"
                phx-click="toggle_effective_permissions"
                class="flex items-center gap-2 w-full text-left group cursor-pointer focus:outline-none"
              >
                <span class="shrink-0 text-ink-muted w-3 grid place-items-center" aria-hidden="true">
                  <.icon
                    name={
                      if @show_effective_permissions,
                        do: "collapse",
                        else: "expand"
                    }
                    class="size-3"
                  />
                </span>
                <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                  Effective Permissions
                  <span class="ml-1.5 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink">
                    {length(@effective_keys)}
                  </span>
                </h3>
              </button>

              <div :if={@show_effective_permissions} id="effective-permissions-content" class="mt-3">
                <p class="text-xs text-ink-muted mb-3">
                  Green = from roles. Blue = direct grant. Red = denied. Click ✕ to remove or deny.
                </p>

                <%= if @grouped_effective_permissions == %{} do %>
                  <p class="text-sm text-ink-muted">No permissions.</p>
                <% else %>
                  <dl
                    :for={{domain, caps} <- @grouped_effective_permissions}
                    id={"permissions-domain-#{domain}"}
                    class="mb-3"
                  >
                    <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-1">
                      {domain}
                    </dt>
                    <dd class="flex flex-wrap gap-1">
                      <%= for cap <- caps do %>
                        <% is_direct = Map.has_key?(@direct_grant_ids, cap) %>
                        <span
                          id={"cap-badge-#{String.replace(cap, ".", "-")}"}
                          class={[
                            "inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium border",
                            if(is_direct,
                              do: "bg-info-surface text-info-ink border-info-line",
                              else: "bg-success-surface text-success-ink border-success-line"
                            )
                          ]}
                        >
                          <span>{cap}</span>
                          <%= if @can_manage? do %>
                            <%= if is_direct do %>
                              <.icon_button
                                icon="close"
                                label={"Remove the direct grant of #{cap}"}
                                context={:inline}
                                kind={:danger}
                                id={"remove-direct-cap-#{String.replace(cap, ".", "-")}"}
                                phx-click="remove_capability"
                                phx-value-grant-id={@direct_grant_ids[cap]}
                                data-confirm={
                                  "Remove the direct grant of #{cap} from #{@user.name}? " <>
                                    "They keep this capability only if an assigned role " <>
                                    "still grants it."
                                }
                              />
                            <% else %>
                              <%= if not is_nil(@user.company_id) do %>
                                <.icon_button
                                  icon="close"
                                  label={"Deny #{cap}"}
                                  context={:inline}
                                  kind={:danger}
                                  id={"deny-cap-#{String.replace(cap, ".", "-")}"}
                                  phx-click="deny_capability"
                                  phx-value-capability-key={cap}
                                  data-confirm={
                                    "Deny #{cap} for #{@user.name}? This overrides every " <>
                                      "role that grants it and takes effect immediately."
                                  }
                                />
                              <% end %>
                            <% end %>
                          <% end %>
                        </span>
                      <% end %>
                    </dd>
                  </dl>
                <% end %>

                <!-- Denied Capabilities Grouped by Domain (Red) -->
                <div
                  :if={@grouped_denied_permissions != %{}}
                  id="denied-permissions-section"
                  class="mt-4 pt-4 border-t border-line"
                >
                  <div class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-2">
                    Denied
                  </div>
                  <div
                    :for={{domain, caps} <- @grouped_denied_permissions}
                    id={"denied-domain-#{domain}"}
                    class="mb-3"
                  >
                    <div class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-1">
                      {domain}
                    </div>
                    <div class="flex flex-wrap gap-1">
                      <span
                        :for={cap <- caps}
                        id={"denied-cap-badge-#{String.replace(cap, ".", "-")}"}
                        class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium border border-danger-line bg-danger-surface text-danger-ink"
                      >
                        <span>{cap}</span>
                        <.icon_button
                          :if={@can_manage?}
                          icon="close"
                          label={"Remove the deny rule for #{cap}"}
                          context={:inline}
                          kind={:danger}
                          id={"remove-denial-#{String.replace(cap, ".", "-")}"}
                          phx-click="remove_capability"
                          phx-value-grant-id={@direct_deny_ids[cap]}
                          data-confirm={
                            "Remove the deny rule for #{cap}? #{@user.name} regains this " <>
                              "capability from any role or direct grant that provides it."
                          }
                        />
                      </span>
                    </div>
                  </div>
                </div>

                <!-- Add Capabilities Picker -->
                <div
                  :if={
                    @can_manage? and not is_nil(@user.company_id) and
                      @grouped_available_capabilities != %{}
                  }
                  id="add-capabilities-section"
                  class="mt-4 pt-4 border-t border-line"
                >
                  <div class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-2">
                    Add Capabilities
                  </div>
                  <input
                    type="text"
                    id="capability-search-input"
                    phx-input="search_capabilities"
                    placeholder="Search capabilities..."
                    value={@capability_search}
                    class="w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none mb-2"
                  />
                  <form
                    phx-change="select_capabilities"
                    phx-submit="add_selected_capabilities"
                    id="add-capabilities-form"
                  >
                    <div
                      class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-1 max-h-48 overflow-y-auto"
                      id="available-capabilities-list"
                    >
                      <%= for {_domain, caps} <- @grouped_available_capabilities, cap <- caps, String.contains?(String.downcase(cap), String.downcase(@capability_search)) do %>
                        <label
                          id={"available-cap-label-#{String.replace(cap, ".", "-")}"}
                          class="flex items-center gap-2 px-2 py-1 rounded text-sm hover:bg-surface-sunken cursor-pointer text-ink"
                        >
                          <input
                            type="checkbox"
                            name="capability_keys[]"
                            value={cap}
                            checked={cap in @selected_capability_keys}
                            class="rounded border-high-contrast-line accent-action focus:ring-brand-strong/30"
                          />
                          <span class="truncate" title={cap}>{cap}</span>
                        </label>
                      <% end %>
                    </div>
                    <div :if={@selected_capability_keys != []} class="mt-2">
                      <.button
                        type="submit"
                        variant="primary"
                        id="confirm-add-capabilities-btn"
                        class="text-xs"
                      >
                        Add ({length(@selected_capability_keys)})
                      </.button>
                    </div>
                  </form>
                </div>
              </div>
            </div>
          </.card>

          <!-- Card 3: Change Password -->
          <.card id="user-password-card" inner_class="p-5 sm:p-6">
            <button
              type="button"
              id="toggle-change-password-btn"
              phx-click="toggle_change_password"
              class="flex items-center gap-2 w-full text-left group cursor-pointer focus:outline-none"
            >
              <span class="shrink-0 text-ink-muted w-3 grid place-items-center" aria-hidden="true">
                <.icon
                  name={if @show_change_password, do: "collapse", else: "expand"}
                  class="size-3"
                />
              </span>
              <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                Change Password
              </h3>
            </button>

            <div :if={@show_change_password} id="change-password-form-container" class="mt-4 max-w-md">
              <.form
                for={@password_form}
                id="user-password-form"
                phx-submit="update_password"
                class="space-y-4"
              >
                <div>
                  <label for="user-new-password" class="mb-1.5 block text-sm font-medium text-ink">New Password</label>
                  <input
                    type="password"
                    name="password"
                    id="user-new-password"
                    required
                    autocomplete="new-password"
                    placeholder="Enter new password"
                    class="block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-2 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/20"
                  />
                  <p
                    :if={@password_errors[:password]}
                    class="mt-1.5 flex items-center gap-1.5 text-sm text-danger-ink"
                  >
                    <.icon name="error" class="size-4 shrink-0 text-danger" />
                    {@password_errors[:password]}
                  </p>
                </div>

                <div>
                  <label
                    for="user-new-password-confirmation"
                    class="mb-1.5 block text-sm font-medium text-ink"
                  >Confirm New Password</label>
                  <input
                    type="password"
                    name="password_confirmation"
                    id="user-new-password-confirmation"
                    required
                    autocomplete="new-password"
                    placeholder="Confirm new password"
                    class="block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-2 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/20"
                  />
                  <p
                    :if={@password_errors[:password_confirmation]}
                    class="mt-1.5 flex items-center gap-1.5 text-sm text-danger-ink"
                  >
                    <.icon name="error" class="size-4 shrink-0 text-danger" />
                    {@password_errors[:password_confirmation]}
                  </p>
                </div>

                <.button type="submit" variant="primary" id="update-password-btn" class="text-sm">
                  Update Password
                </.button>
              </.form>
            </div>
          </.card>

          <!-- Card 4: Employee Records -->
          <.card id="user-employees-card" inner_class="p-5 sm:p-6 space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                Employee Records
                <span
                  id="employees-count"
                  class="ml-1.5 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink"
                >
                  {length(@employees)}
                </span>
              </h3>
              <div :if={@can_manage? and not is_nil(@user.company_id)}>
                <.button
                  type="button"
                  id="open-add-employee-modal-btn"
                  phx-click="open_add_employee_modal"
                  variant="primary"
                  class="text-xs"
                >
                  <.icon name="create" class="size-3.5" />
                  <span>Add Employee</span>
                </.button>
              </div>
            </div>
            <p class="max-w-prose text-xs text-ink-muted mt-0.5">
              Employment records linking this user to companies. A user can have multiple records across different companies (e.g. contractors). Not all employees require a user account.
            </p>

            <.table
              id="user-employees-table"
              rows={@sorted_employees}
              sort_by={@employees_sort_by}
              sort_dir={@employees_sort_dir}
              sort_event="sort_employees"
              framed={false}
            >
              <:col :let={emp} label="Employee No." sort="employee_number">
                <.link
                  navigate={~p"/employees/#{emp.id}"}
                  class="text-action hover:underline font-medium"
                >
                  {emp.employee_number || "—"}
                </.link>
              </:col>
              <:col :let={emp} label="Company" sort="company">
                <%= if Map.get(@company_names, emp.company_id) do %>
                  <.link
                    navigate={~p"/companies/#{emp.company_id}"}
                    class="text-action hover:underline"
                  >
                    {Map.get(@company_names, emp.company_id)}
                  </.link>
                <% else %>
                  <span class="text-ink-faint">—</span>
                <% end %>
              </:col>
              <:col :let={emp} label="Department" sort="department">
                <span class="text-ink-muted">{Map.get(@department_names, emp.department_id) || "—"}</span>
              </:col>
              <:col :let={emp} label="Designation" sort="designation">
                <span class="text-ink-muted">{emp.designation || "—"}</span>
              </:col>
              <:col :let={emp} label="Status" sort="status">
                <.badge kind={employee_status_kind(emp.status)}>
                  {String.capitalize(emp.status || "active")}
                </.badge>
              </:col>
              <:col :let={emp} label="Employment Start" sort="employment_start">
                <span class="text-ink-muted tabular-nums">
                  <.datetime
                    :if={emp.employment_start}
                    id={"employee-start-#{emp.id}"}
                    value={emp.employment_start}
                  />
                  <span :if={is_nil(emp.employment_start)} class="text-ink-faint">—</span>
                </span>
              </:col>
              <:action :let={emp}>
                <.icon_button
                  :if={@can_manage?}
                  icon="unlink"
                  label={"Unlink #{emp.full_name}"}
                  kind={:danger}
                  id={"unlink-employee-#{emp.id}"}
                  phx-click="unlink_employee"
                  phx-value-employee-id={emp.id}
                  data-confirm="Unlink this employee record from the user?"
                />
              </:action>
              <:empty :if={@employees == []}>
                No employee records.
              </:empty>
            </.table>

            <!-- Link Existing Employee Form -->
            <div
              :if={@can_manage? and @unlinkable_employees != []}
              id="link-employee-section"
              class="mt-4 pt-4 border-t border-line"
            >
              <div :if={not @show_link_employee}>
                <.button
                  type="button"
                  id="toggle-link-employee-btn"
                  phx-click="toggle_link_employee"
                  class="text-xs"
                >
                  <.icon name="create" class="size-3.5" />
                  <span>Link Employee</span>
                </.button>
              </div>
              <div
                :if={@show_link_employee}
                class="flex items-center gap-2"
                id="link-employee-form-container"
              >
                <form
                  phx-submit="link_employee"
                  id="link-employee-form"
                  class="flex items-center gap-2"
                >
                  <select
                    name="employee_id"
                    id="link-employee-select"
                    class="w-64 rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  >
                    <option value="">Search employee...</option>
                    <option
                      :for={emp <- @unlinkable_employees}
                      value={emp.id}
                    >
                      {emp.full_name} ({emp.employee_number})
                    </option>
                  </select>
                  <.button
                    type="submit"
                    variant="primary"
                    id="confirm-link-employee-btn"
                    class="text-xs"
                  >
                    Link
                  </.button>
                  <.button type="button" phx-click="toggle_link_employee" class="text-xs">
                    Cancel
                  </.button>
                </form>
              </div>
            </div>
          </.card>

          <!-- Card 5: External Accesses -->
          <.card id="user-external-accesses-card" inner_class="p-5 sm:p-6 space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
                External Accesses
                <span
                  id="external-accesses-count"
                  class="ml-1.5 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink"
                >
                  {length(@external_accesses)}
                </span>
              </h3>
            </div>
            <p class="max-w-prose text-xs text-ink-muted mt-0.5">
              Portal access granted to this user by other companies. Allows customers or suppliers to view orders, invoices, and other shared data.
            </p>

            <.table
              id="user-external-accesses-table"
              rows={@sorted_external_accesses}
              sort_by={@external_accesses_sort_by}
              sort_dir={@external_accesses_sort_dir}
              sort_event="sort_external_accesses"
              framed={false}
            >
              <:col :let={access} label="Granting Company" sort="company">
                <%= if Map.get(@company_names, access.company_id) do %>
                  <.link
                    navigate={~p"/companies/#{access.company_id}"}
                    class="text-action hover:underline font-medium"
                  >
                    {Map.get(@company_names, access.company_id)}
                  </.link>
                <% else %>
                  <span class="text-ink-faint">—</span>
                <% end %>
              </:col>
              <:col :let={access} label="Permissions" sort="permissions">
                <%= if is_list(access.permissions) and access.permissions != [] do %>
                  <div class="flex flex-wrap gap-1">
                    <span
                      :for={p <- access.permissions}
                      class="inline-flex rounded bg-surface-muted px-1.5 py-0.5 text-[11px] text-ink"
                    >
                      {p}
                    </span>
                  </div>
                <% else %>
                  <span class="text-ink-faint">—</span>
                <% end %>
              </:col>
              <:col :let={access} label="Status" sort="access_status">
                <.badge kind={external_access_status_kind(access)}>
                  {external_access_status_label(access)}
                </.badge>
              </:col>
              <:col :let={access} label="Granted At" sort="granted_at">
                <span class="text-ink-muted tabular-nums">
                  <.datetime
                    :if={access.access_granted_at}
                    id={"access-granted-#{access.id}"}
                    value={access.access_granted_at}
                  />
                  <span :if={is_nil(access.access_granted_at)} class="text-ink-faint">—</span>
                </span>
              </:col>
              <:col :let={access} label="Expires At" sort="expires_at">
                <span class="text-ink-muted tabular-nums">
                  <.datetime
                    :if={access.access_expires_at}
                    id={"access-expires-#{access.id}"}
                    value={access.access_expires_at}
                  />
                  <span :if={is_nil(access.access_expires_at)} class="text-ink-faint">—</span>
                </span>
              </:col>
              <:empty :if={@external_accesses == []}>
                No external accesses.
              </:empty>
            </.table>
          </.card>

          <!-- Card 6: Danger Zone (Delete Account) -->
          <section
            :if={allowed?(@current_scope, "admin.user.delete")}
            id="user-danger"
            class="rounded-xl border border-danger-line bg-danger-surface px-5 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div>
                <h2 class="text-sm font-semibold text-danger-ink">Delete this user</h2>
                <p class="mt-0.5 text-xs text-danger-ink">
                  Permanently deletes this account. This cannot be undone.
                </p>
              </div>
              <.button
                id="user-delete"
                variant="danger"
                phx-click="delete"
                data-confirm={"Delete #{@user.name}? This cannot be undone."}
              >
                Delete user
              </.button>
            </div>
          </section>
        </div>

        <.modal
          :if={@show_add_employee_modal}
          id="add-employee-modal"
          title="Add Employee Record"
          flash={@flash}
          on_cancel={JS.push("close_add_employee_modal")}
        >
          <:description>Create a new employee record and link it to this user.</:description>
            <.form
              for={@new_employee_form}
              id="modal-create-employee-form"
              phx-submit="save_new_employee"
              class="mt-4 space-y-4"
            >
              <div>
                <label for="new-emp-company" class="block text-xs font-medium text-ink">Company</label>
                <select
                  name="company_id"
                  id="new-emp-company"
                  required
                  class="mt-1 block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                >
                  <option
                    :for={company <- @companies}
                    value={company.id}
                    selected={@new_employee_form[:company_id].value == company.id}
                  >
                    {Company.Summary.display_name(company)}
                  </option>
                </select>
                <p :if={@new_employee_errors[:company_id]} class="mt-1 text-xs text-danger-ink">
                  {@new_employee_errors[:company_id]}
                </p>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label for="new-emp-number" class="block text-xs font-medium text-ink">Employee Number</label>
                  <input
                    type="text"
                    name="employee_number"
                    id="new-emp-number"
                    required
                    value={@new_employee_form[:employee_number].value}
                    class="mt-1 block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                  <p :if={@new_employee_errors[:employee_number]} class="mt-1 text-xs text-danger-ink">
                    {@new_employee_errors[:employee_number]}
                  </p>
                </div>
                <div>
                  <label for="new-emp-name" class="block text-xs font-medium text-ink">Full Name</label>
                  <input
                    type="text"
                    name="full_name"
                    id="new-emp-name"
                    required
                    value={@new_employee_form[:full_name].value}
                    class="mt-1 block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                  <p :if={@new_employee_errors[:full_name]} class="mt-1 text-xs text-danger-ink">
                    {@new_employee_errors[:full_name]}
                  </p>
                </div>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label for="new-emp-designation" class="block text-xs font-medium text-ink">Designation</label>
                  <input
                    type="text"
                    name="designation"
                    id="new-emp-designation"
                    placeholder="Job title"
                    value={@new_employee_form[:designation].value}
                    class="mt-1 block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                </div>
                <div>
                  <label for="new-emp-start" class="block text-xs font-medium text-ink">Employment Start</label>
                  <input
                    type="date"
                    name="employment_start"
                    id="new-emp-start"
                    value={@new_employee_form[:employment_start].value}
                    class="mt-1 block w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                </div>
              </div>

              <div class="mt-6 flex justify-end gap-2">
                <.button
                  type="button"
                  phx-click="close_add_employee_modal"
                  id="cancel-add-employee-btn"
                  class="text-xs"
                >
                  Cancel
                </.button>
                <.button type="submit" variant="primary" id="confirm-add-employee-btn" class="text-xs">
                  Create & Link
                </.button>
              </div>
            </.form>
        </.modal>
      </.page>
    </Layouts.app>
    """
  end

  # --- Fact Components ---

  # A read-first text fact. An operator who may update edits it in place;
  # anyone else — a viewer, or any actor while the account has no company to
  # write through — sees the stored value with no affordance. Name and email
  # are required columns, so an emptied input is not a commit.
  attr(:name, :string, required: true)
  attr(:user, :map, required: true)
  attr(:can_manage?, :boolean, required: true)
  attr(:field_status, :map, required: true)

  defp text_fact(assigns) do
    assigns =
      assigns
      |> assign(:label, fact_label(assigns.name))
      |> assign(:value, Map.fetch!(assigns.user, Map.fetch!(@inline_fields, assigns.name)))
      |> assign(:editable?, assigns.can_manage?)

    ~H"""
    <div id={"user-detail-#{@name}"}>
      <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">{@label}</dt>
      <dd id={"user-view-#{@name}"} class="mt-0.5 text-sm text-ink">
        <.inline_edit
          :if={@editable?}
          id={"user-#{@name}"}
          name={@name}
          label={@label}
          value={@value}
          id_value={@user.id}
          save_event="save_field"
          status={@field_status[@name]}
        />
        <span :if={not @editable?}>{@value}</span>
      </dd>
    </div>
    """
  end

  # --- Private Helpers ---

  # The guard is unchanged from the header it replaced: the capability, never
  # the signed-in account, and never while already impersonating.
  defp can_impersonate?(current_scope, user) do
    allowed?(current_scope, "admin.user.impersonate") and
      user.id != current_scope.user["user_id"] and
      is_nil(current_scope.impersonator)
  end

  # One commit, one outcome on the fact that made it. Success reloads the
  # detail so every projection (title, subtitle, roles scope) is the
  # server's; refusal keeps the stored value on screen and says what was
  # rejected and why.
  defp save_fact(socket, name, attrs, submitted) do
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user

    case User.update_user(scope, user.company_id, user.id, attrs) do
      {:ok, updated_user} ->
        socket
        |> load_data(updated_user)
        |> CommitStatus.put(name, :saved)

      {:error, %Ecto.Changeset{} = changeset} ->
        CommitStatus.put(socket, name, {:error, refusal_message(name, submitted, changeset)})

      {:error, reason} ->
        CommitStatus.put(socket, name, {:error, failure_message(reason)})
    end
  end

  # The choice fact reports on the schema field it writes; the shared wording
  # names the rejected value and the label.
  defp refusal_message(name, submitted, %Ecto.Changeset{} = changeset) do
    field = Map.get(@inline_fields, name, :company_id)
    CommitStatus.refusal_message(fact_label(name), field, submitted, changeset.errors)
  end

  defp failure_message(:user_not_found),
    do: "This user no longer exists. Return to the list to find their replacement."

  defp failure_message(:company_not_found),
    do: "The change was not saved because this user's company could not be found."

  defp failure_message(_reason), do: CommitStatus.failure_message()

  # A refusal names the rule that applied and the company it was evaluated
  # against. A reassignment authorizes `admin.user.update` on the account's
  # CURRENT company, so naming the chosen one would point at the wrong rule.
  defp company_failure_message(:unauthorized, choice, company_name),
    do: "#{inspect(choice)} was not saved: you may not manage users of #{company_name}."

  defp company_failure_message(:company_not_found, choice, _company_name),
    do: "#{inspect(choice)} was not saved: that company is not in this workspace."

  defp company_failure_message(reason, _choice, _company_name),
    do: failure_message(reason)

  # The select offers no blank option; a blank that still arrives is refused
  # in the words the product means, not as a missing company.
  defp detach_refused_message,
    do: "The change was not saved: a user always belongs to a company."

  defp commit_company(socket, result, choice) do
    company_name = socket.assigns.company_name
    socket = close_company_editor(socket)

    case result do
      {:ok, updated_user} ->
        socket
        |> load_data(updated_user)
        |> CommitStatus.put("company", :saved)

      {:error, %Ecto.Changeset{} = changeset} ->
        CommitStatus.put(
          socket,
          "company",
          {:error, refusal_message("company", choice, changeset)}
        )

      {:error, reason} ->
        CommitStatus.put(
          socket,
          "company",
          {:error, company_failure_message(reason, choice, company_name)}
        )
    end
  end

  defp close_company_editor(socket), do: assign(socket, :editing_field, nil)

  defp chosen_company_id(params) do
    company_id_param =
      case params do
        %{"company_id" => cid} -> cid
        %{"user" => %{"company_id" => cid}} -> cid
        cid when is_binary(cid) -> cid
        _ -> ""
      end

    case Integer.parse(to_string(company_id_param)) do
      {cid, ""} when cid > 0 -> cid
      _ -> nil
    end
  end

  # What the operator chose, as the alert names it: the company's display
  # name when the option came from this workspace's list, and the raw ID for
  # anything else.
  defp company_choice_label(socket, company_id) do
    Map.get(socket.assigns.company_names, company_id, Integer.to_string(company_id))
  end

  defp write_forbidden(socket),
    do: CommitStatus.write_forbidden(socket, "You do not have permission to edit users.")

  defp fact_label(name), do: Map.fetch!(@fact_labels, name)

  defp current_actor(socket, company_id) do
    current_scope = socket.assigns.current_scope

    target_company_id =
      company_id || current_scope[:active_company_id] ||
        (current_scope[:actor] && current_scope.actor.company_id) ||
        (is_map(current_scope[:user]) && current_scope.user["company_id"])

    if is_nil(company_id) and current_scope[:actor] do
      current_scope.actor
    else
      user_id =
        (current_scope[:actor] && current_scope.actor.id) ||
          (is_map(current_scope[:user]) &&
             (current_scope.user["user_id"] || current_scope.user["id"]))

      Authz.actor(:user, user_id, current_scope.scope, target_company_id)
    end
  end

  defp group_by_domain(caps) do
    caps
    |> Enum.sort()
    |> Enum.group_by(fn cap ->
      case String.split(cap, ".") do
        [domain | _] -> domain
        _ -> "other"
      end
    end)
  end

  defp filter_roles(roles, query) do
    q = String.downcase(String.trim(query))

    if q == "" do
      roles
    else
      Enum.filter(roles, &String.contains?(String.downcase(&1.name), q))
    end
  end

  defp validate_password_params(password, confirmation) do
    errors = %{}

    errors =
      cond do
        password == "" ->
          Map.put(errors, :password, "can't be blank")

        String.length(password) < 8 ->
          Map.put(errors, :password, "should be at least 8 character(s)")

        true ->
          errors
      end

    errors =
      cond do
        confirmation == "" ->
          Map.put(errors, :password_confirmation, "can't be blank")

        confirmation != password ->
          Map.put(errors, :password_confirmation, "Passwords do not match")

        true ->
          errors
      end

    errors
  end

  defp employee_status_kind("active"), do: :success
  defp employee_status_kind("pending"), do: :warning
  defp employee_status_kind("terminated"), do: :danger
  defp employee_status_kind(_), do: :neutral

  defp external_access_status_kind(access) do
    cond do
      Company.ExternalAccessSummary.valid?(access) ->
        :success

      match?(%NaiveDateTime{}, access.access_expires_at) and
          NaiveDateTime.compare(access.access_expires_at, NaiveDateTime.utc_now()) == :lt ->
        :danger

      match?(%NaiveDateTime{}, access.access_granted_at) and
          NaiveDateTime.compare(access.access_granted_at, NaiveDateTime.utc_now()) == :gt ->
        :warning

      true ->
        :neutral
    end
  end

  defp external_access_status_label(access) do
    cond do
      Company.ExternalAccessSummary.valid?(access) ->
        "Valid"

      match?(%NaiveDateTime{}, access.access_expires_at) and
          NaiveDateTime.compare(access.access_expires_at, NaiveDateTime.utc_now()) == :lt ->
        "Expired"

      match?(%NaiveDateTime{}, access.access_granted_at) and
          NaiveDateTime.compare(access.access_granted_at, NaiveDateTime.utc_now()) == :gt ->
        "Pending"

      true ->
        "Inactive"
    end
  end

  defp sort_employees(employees, column, dir, company_names, department_names) do
    employees
    |> Enum.sort_by(
      fn emp ->
        case column do
          "company" -> Map.get(company_names, emp.company_id, "")
          "department" -> Map.get(department_names, emp.department_id, "")
          "designation" -> emp.designation || ""
          "status" -> emp.status || ""
          "employment_start" -> emp.employment_start || ~D[1900-01-01]
          _ -> emp.employee_number || ""
        end
      end,
      if(dir == "desc", do: :desc, else: :asc)
    )
  end

  defp sort_external_accesses(accesses, column, dir, company_names) do
    accesses
    |> Enum.sort_by(
      fn access ->
        case column do
          "company" -> Map.get(company_names, access.company_id, "")
          "permissions" -> length(access.permissions || [])
          "access_status" -> external_access_status_label(access)
          "granted_at" -> access.access_granted_at || ~N[1900-01-01 00:00:00]
          "expires_at" -> access.access_expires_at || ~N[1900-01-01 00:00:00]
          _ -> access.id
        end
      end,
      if(dir == "desc", do: :desc, else: :asc)
    )
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That user does not exist in this workspace.")
    |> push_navigate(to: ~p"/users")
  end

  defp acting_grant_all?(current_scope) do
    case current_scope do
      %{actor: %Authz.Actor{type: type, id: id}, scope: scope} ->
        assignments = Authz.list_principal_role_assignments(scope, type, id, page_size: 100)
        Enum.any?(assignments.entries, & &1.role_grant_all)

      _ ->
        false
    end
  end

  defp acting_allowed_capabilities(current_scope) do
    case current_scope do
      %{actor: %Authz.Actor{} = actor} ->
        Authz.effective_capabilities(actor).allowed

      %{capabilities: caps} when is_list(caps) ->
        caps

      _ ->
        []
    end
  end

  defp role_grantable?(scope, role_id, acting_grant_all?, %MapSet{} = acting_allowed_set) do
    case Authz.get_role(scope, role_id) do
      {:ok, %{role: %{grant_all: true}}} ->
        acting_grant_all?

      {:ok, %{capabilities: caps}} ->
        acting_grant_all? or Enum.all?(caps, &MapSet.member?(acting_allowed_set, &1))

      _ ->
        false
    end
  end

  # The mount-time assign hides controls; it is presentation state. Every
  # write asks again, because a LiveView process outlives its mount and a
  # revoked grant must not keep working until remount (#609, the #482/#541
  # pattern).
  defp can_manage?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @manage_capability).allowed
  end
end
