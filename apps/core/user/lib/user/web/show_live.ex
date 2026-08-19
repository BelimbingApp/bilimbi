defmodule Bilimbi.Core.User.Web.ShowLive do
  @moduledoc """
  Shows one tenant-visible user and provides administrative management:
  inline editing, roles and capability assignments, password updates,
  employee linking/creation, and external accesses read model.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
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
        |> assign(:page_title, user.name)
        |> assign(:active_nav, "admin.user")
        |> assign(:user_id, user_id)
        |> init_ui_state()
        |> load_data(user)

      {:ok, socket}
    else
      _ -> {:ok, not_found(socket)}
    end
  end

  defp init_ui_state(socket) do
    socket
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
    can_manage? = allowed?(current_scope, "admin.user.update")

    {:ok, companies} = Company.list_companies(scope)
    company_names = Map.new(companies, &{&1.id, Company.Summary.display_name(&1)})

    # Assigned roles
    role_page = Authz.list_principal_role_assignments(scope, :user, user.id, page_size: 100)
    assigned_roles = role_page.entries
    assigned_role_ids = Enum.map(assigned_roles, & &1.role_id)
    has_grant_all? = Enum.any?(assigned_roles, & &1.role_grant_all)

    # Available roles for assignment
    all_roles = Authz.list_roles(scope)
    available_roles = Enum.reject(all_roles, &(&1.id in assigned_role_ids))

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

    # Available capabilities (all registry capabilities minus effective minus denied)
    excluded_keys = MapSet.new(effective_keys ++ denied_keys)
    all_registered_caps = Authz.capabilities() |> Enum.sort()
    available_caps = Enum.reject(all_registered_caps, &MapSet.member?(excluded_keys, &1))
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

    socket
    |> assign(:user, user)
    |> assign(:can_manage?, can_manage?)
    |> assign(:companies, companies)
    |> assign(:company_names, company_names)
    |> assign(:company_name, Map.get(company_names, user.company_id))
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
        company_names
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

  # --- Event Handlers: Inline Editing ---

  @impl true
  def handle_event("save_field", params, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      {field, value} =
        cond do
          Map.has_key?(params, "name") -> {:name, Map.get(params, "name")}
          Map.has_key?(params, "email") -> {:email, Map.get(params, "email")}
          Map.get(params, "field") == "name" -> {:name, Map.get(params, "value")}
          Map.get(params, "field") == "email" -> {:email, Map.get(params, "value")}
          true -> {nil, nil}
        end

      if field do
        case User.update_user(scope, user.company_id, user.id, %{field => value}) do
          {:ok, updated_user} ->
            field_name = if field == :name, do: "Name", else: "Email"

            {:noreply,
             socket
             |> put_flash(:info, "#{field_name} updated successfully.")
             |> load_data(updated_user)}

          {:error, _changeset} ->
            field_name = if field == :name, do: "name", else: "email"
            {:noreply, put_flash(socket, :error, "Failed to update #{field_name}.")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit users.")}
    end
  end

  def handle_event("save_company", params, socket) do
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      company_id_param =
        case params do
          %{"company_id" => cid} -> cid
          %{"user" => %{"company_id" => cid}} -> cid
          cid when is_binary(cid) -> cid
          _ -> ""
        end

      target_company_id =
        case Integer.parse(to_string(company_id_param)) do
          {cid, ""} when cid > 0 -> cid
          _ -> nil
        end

      result =
        cond do
          user.company_id == target_company_id ->
            {:ok, user}

          not is_nil(user.company_id) and not is_nil(target_company_id) ->
            actor = current_actor(socket, user.company_id)
            User.reassign_user_company(actor, scope, user.company_id, user.id, target_company_id)

          not is_nil(user.company_id) and is_nil(target_company_id) ->
            actor = current_actor(socket, user.company_id)
            User.clear_user_company(actor, scope, user.company_id, user.id)

          is_nil(user.company_id) and not is_nil(target_company_id) ->
            actor = current_actor(socket, target_company_id)
            User.assign_unaffiliated_user(actor, scope, user.id, target_company_id)

          true ->
            {:ok, user}
        end

      case result do
        {:ok, updated_user} ->
          msg =
            cond do
              is_nil(target_company_id) ->
                "User is now unaffiliated with any company."

              not is_nil(user.company_id) and user.company_id != target_company_id ->
                "Company reassigned."

              true ->
                "Company assignment saved."
            end

          {:noreply,
           socket
           |> put_flash(:info, msg)
           |> load_data(updated_user)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update company assignment.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to edit users.")}
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
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      role_ids =
        case Map.get(params, "role_ids") do
          ids when is_list(ids) and ids != [] -> ids
          _ -> socket.assigns.selected_role_ids
        end

      if user.company_id && role_ids != [] do
        for role_id_str <- role_ids,
            {role_id, ""} <- [Integer.parse(role_id_str)] do
          Authz.assign_role(scope, user.company_id, :user, user.id, role_id)
        end

        count = length(role_ids)
        msg = if count == 1, do: "Assigned 1 role.", else: "Assigned #{count} roles."

        {:noreply,
         socket
         |> put_flash(:info, msg)
         |> assign(:selected_role_ids, [])
         |> assign(:show_assign_roles, false)
         |> load_data(user)}
      else
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
      scope = socket.assigns.current_scope.scope
      user = socket.assigns.user

      cap_keys =
        case Map.get(params, "capability_keys") do
          keys when is_list(keys) and keys != [] -> keys
          _ -> socket.assigns.selected_capability_keys
        end

      if user.company_id && cap_keys != [] do
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
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage capabilities.")}
    end
  end

  def handle_event("deny_capability", %{"capability-key" => cap_key}, socket) do
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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
    if socket.assigns.can_manage? do
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
      sort_employees(socket.assigns.employees, sort_col, new_dir, socket.assigns.company_names)

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
          <:subtitle>
            <%= if @company_name do %>
              {@company_name}
            <% else %>
              Unaffiliated
            <% end %>
          </:subtitle>
          <:actions>
            <.button id="user-back" navigate={~p"/users"}>
              Back
            </.button>
            <.link
              :if={
                allowed?(@current_scope, "admin.user.impersonate") and
                  @user.id != @current_scope.user["user_id"] and
                  is_nil(@current_scope.impersonator)
              }
              id="user-impersonate"
              href={~p"/admin/impersonate/#{@user.id}"}
              method="post"
              class="inline-flex items-center gap-1.5 rounded-lg border border-line bg-surface px-3 py-1.5 text-xs font-semibold text-ink shadow-xs transition hover:bg-surface-sunken"
            >
              <.icon name="bilimbi-impersonate" class="size-4" />
              <span>Impersonate</span>
            </.link>
            <.button
              :if={@can_manage?}
              id="user-edit"
              navigate={~p"/users/#{@user.id}/edit"}
              variant="primary"
            >
              Edit user
            </.button>
          </:actions>
        </.header>

        <div class="mt-6 space-y-6">
          <!-- Card 1: User Details with In-place Editing -->
          <.card id="user-details-card">
            <div class="p-4 space-y-4">
              <div class="border-b border-line pb-2">
                <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">User Details</h3>
              </div>

              <dl class="grid grid-cols-1 gap-4 md:grid-cols-2">
                <div id="user-detail-name">
                  <dt class="text-xs text-ink-muted">Name</dt>
                  <dd class="mt-0.5 text-sm text-ink">
                  <%= if @can_manage? do %>
                    <.inline_edit
                      id="user-name"
                      name="name"
                      label="Name"
                      value={@user.name}
                      id_value={@user.id}
                      save_event="save_field"
                    />
                  <% else %>
                    <span>{@user.name}</span>
                  <% end %>
                  </dd>
                </div>

                <div id="user-detail-email">
                  <dt class="text-xs text-ink-muted">Email</dt>
                  <dd class="mt-0.5 text-sm text-ink">
                  <%= if @can_manage? do %>
                    <.inline_edit
                      id="user-email"
                      name="email"
                      label="Email"
                      value={@user.email}
                      id_value={@user.id}
                      save_event="save_field"
                    />
                  <% else %>
                    <span>{@user.email}</span>
                  <% end %>
                  </dd>
                </div>

                <div id="user-detail-company">
                  <dt class="text-xs text-ink-muted">Company</dt>
                  <dd class="mt-0.5 text-sm text-ink">
                  <%= if @can_manage? do %>
                    <form phx-change="save_company" id="user-company-form" class="inline-block">
                      <select
                        id="user-company-select"
                        name="company_id"
                        class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                      >
                        <option value="" selected={is_nil(@user.company_id)}>None</option>
                        <option
                          :for={company <- @companies}
                          value={company.id}
                          selected={@user.company_id == company.id}
                        >
                          {Company.Summary.display_name(company)}
                        </option>
                      </select>
                    </form>
                  <% else %>
                    <%= if @company_name do %>
                      <.link navigate={~p"/companies/#{@user.company_id}"} class="text-ink-muted hover:text-ink hover:underline">
                        {@company_name}
                      </.link>
                    <% else %>
                      <span class="text-ink-faint">None</span>
                    <% end %>
                  <% end %>
                  </dd>
                </div>

                <div id="user-detail-email-verified">
                  <dt class="text-xs text-ink-muted">Email Verified</dt>
                  <dd class="mt-0.5 text-sm text-ink">
                  <.badge kind={if @user.email_verified_at, do: :success, else: :warning}>
                    {if @user.email_verified_at, do: "verified", else: "unverified"}
                  </.badge>
                  </dd>
                </div>

                <div id="user-detail-created">
                  <dt class="text-xs text-ink-muted">Created</dt>
                  <dd class="mt-0.5 text-sm text-ink">
                  <.datetime id="user-created-at" :if={@user.created_at} value={@user.created_at} />
                  <span :if={is_nil(@user.created_at)} class="text-ink-faint">—</span>
                  </dd>
                </div>

                <div id="user-detail-updated">
                  <dt class="text-xs text-ink-muted">Updated</dt>
                  <dd class="mt-0.5 text-sm text-ink">
                  <.datetime id="user-updated-at" :if={@user.updated_at} value={@user.updated_at} />
                  <span :if={is_nil(@user.updated_at)} class="text-ink-faint">—</span>
                  </dd>
                </div>
              </dl>
            </div>
          </.card>

          <!-- Card 2: Roles & Permissions -->
          <.card id="user-roles-card">
            <div class="p-4 space-y-4">
              <div class="flex items-center justify-between border-b border-line pb-2">
                <div class="flex items-center gap-2">
                  <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">Roles & Permissions</h3>
                  <span id="assigned-roles-count"><.badge kind={:neutral}>{length(@assigned_roles)}</.badge></span>
                </div>
                <div :if={@can_manage? and not is_nil(@user.company_id) and @available_roles != []}>
                  <.button
                    type="button"
                    id="toggle-assign-roles-btn"
                    phx-click="toggle_assign_roles"
                    class="text-xs"
                  >
                    {if @show_assign_roles, do: "Close Roles", else: "+ Roles"}
                  </.button>
                </div>
              </div>

              <p class="-mt-2 text-xs text-ink-muted">
                Roles determine what this user can do. Each role grants a set of capabilities.
                Effective permissions show the combined result of all assigned roles.
              </p>

              <%= if is_nil(@user.company_id) do %>
                <.alert kind={:info} id="roles-unaffiliated-alert">
                  User must be assigned to a company before roles and permissions can be managed.
                </.alert>
              <% else %>
                <!-- Assigned Roles Chips -->
                <div id="assigned-roles-container">
                  <div class="text-[11px] font-semibold uppercase tracking-wider text-ink-subtle mb-2">Assigned Roles</div>
                  <%= if @assigned_roles == [] do %>
                    <p class="text-xs text-ink-muted" id="no-roles-msg">No roles assigned.</p>
                  <% else %>
                    <div class="flex flex-wrap gap-1.5" id="assigned-roles-list">
                      <span
                        :for={assignment <- @assigned_roles}
                        id={"assigned-role-#{assignment.id}"}
                        class="inline-flex items-center gap-1 rounded-full border border-line bg-surface-muted px-2.5 py-0.5 text-xs font-medium text-ink"
                      >
                        <span>{assignment.role_name}</span>
                        <button
                          :if={@can_manage?}
                          type="button"
                          id={"remove-role-#{assignment.id}"}
                          phx-click="remove_role"
                          phx-value-assignment-id={assignment.id}
                          phx-value-role-id={assignment.role_id}
                          class="text-ink-muted hover:text-danger ml-0.5"
                          title="Remove role"
                        >
                          ✕
                        </button>
                      </span>
                    </div>
                  <% end %>
                </div>

                <!-- Assign Roles Form (Expandable) -->
                <div
                  :if={@show_assign_roles and @can_manage?}
                  id="assign-roles-picker"
                  class="mt-3 rounded-lg border border-line bg-surface-sunken p-3 space-y-3"
                >
                  <div class="text-[11px] font-semibold uppercase tracking-wider text-ink-subtle">Assign Roles</div>
                  <input
                    type="text"
                    id="role-search-input"
                    phx-input="search_roles"
                    placeholder="Search roles..."
                    value={@role_search}
                    class="w-full rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none"
                  />
                  <form phx-change="select_roles" phx-submit="assign_selected_roles" id="assign-roles-form">
                    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-1.5 max-h-48 overflow-y-auto" id="available-roles-list">
                      <label
                        :for={role <- @filtered_available_roles}
                        id={"available-role-label-#{role.id}"}
                        class="flex items-center gap-2 rounded px-2 py-1 text-xs hover:bg-surface cursor-pointer text-ink"
                      >
                        <input
                          type="checkbox"
                          name="role_ids[]"
                          value={role.id}
                          checked={to_string(role.id) in @selected_role_ids}
                          class="rounded border-line text-action focus:ring-action"
                        />
                        <span class="truncate">{role.name}</span>
                      </label>
                    </div>
                    <div :if={@selected_role_ids != []} class="mt-3 flex items-center gap-2">
                      <.button type="submit" variant="primary" id="confirm-assign-roles-btn" class="text-xs">
                        Assign ({length(@selected_role_ids)})
                      </.button>
                    </div>
                  </form>
                </div>

                <!-- Effective Permissions Disclosure -->
                <div id="effective-permissions-section" class="border-t border-line pt-3">
                  <button
                    type="button"
                    id="toggle-permissions-btn"
                    phx-click="toggle_effective_permissions"
                    class="flex w-full items-center justify-between text-left text-xs font-semibold uppercase tracking-wider text-ink-subtle hover:text-ink"
                  >
                    <span>Effective Permissions</span>
                    <.icon name={if @show_effective_permissions, do: "hero-chevron-up", else: "hero-chevron-down"} class="size-4" />
                  </button>

                  <div :if={@show_effective_permissions} id="effective-permissions-content" class="mt-3 space-y-4">
                    <!-- Allowed Capabilities Grouped by Domain -->
                    <div :for={{domain, caps} <- @grouped_effective_permissions} id={"permissions-domain-#{domain}"} class="space-y-1.5">
                      <h4 class="text-[11px] font-semibold uppercase tracking-wider text-ink-muted">{domain}</h4>
                      <div class="flex flex-wrap gap-1.5">
                        <%= for cap <- caps do %>
                          <% is_direct = Map.has_key?(@direct_grant_ids, cap) %>
                          <span
                            id={"cap-badge-#{String.replace(cap, ".", "-")}"}
                            class={[
                              "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium",
                              if(is_direct, do: "bg-info-surface text-info-ink border border-info-line", else: "bg-success-surface text-success-ink border border-success-line")
                            ]}
                          >
                            <span>{cap}</span>
                            <%= if @can_manage? do %>
                              <%= if is_direct do %>
                                <button
                                  type="button"
                                  id={"remove-direct-cap-#{String.replace(cap, ".", "-")}"}
                                  phx-click="remove_capability"
                                  phx-value-grant-id={@direct_grant_ids[cap]}
                                  class="hover:opacity-70 ml-0.5 text-info-ink"
                                  title="Remove direct grant"
                                >
                                  ✕
                                </button>
                              <% else %>
                                <button
                                  type="button"
                                  id={"deny-cap-#{String.replace(cap, ".", "-")}"}
                                  phx-click="deny_capability"
                                  phx-value-capability-key={cap}
                                  class="hover:opacity-70 ml-0.5 text-success-ink"
                                  title="Deny capability"
                                >
                                  ✕
                                </button>
                              <% end %>
                            <% end %>
                          </span>
                        <% end %>
                      </div>
                    </div>

                    <!-- Denied Capabilities Grouped by Domain (Red) -->
                    <div :if={@grouped_denied_permissions != %{}} id="denied-permissions-section" class="space-y-2 border-t border-line pt-2">
                      <div class="text-[11px] font-semibold uppercase tracking-wider text-danger-ink">Denied Capabilities</div>
                      <div :for={{domain, caps} <- @grouped_denied_permissions} id={"denied-domain-#{domain}"} class="space-y-1.5">
                        <h4 class="text-[11px] font-semibold uppercase tracking-wider text-ink-muted">{domain}</h4>
                        <div class="flex flex-wrap gap-1.5">
                          <span
                            :for={cap <- caps}
                            id={"denied-cap-badge-#{String.replace(cap, ".", "-")}"}
                            class="inline-flex items-center gap-1 rounded-full border border-danger-line bg-danger-surface px-2.5 py-0.5 text-xs font-medium text-danger-ink"
                          >
                            <span>{cap}</span>
                            <button
                              :if={@can_manage?}
                              type="button"
                              id={"remove-denial-#{String.replace(cap, ".", "-")}"}
                              phx-click="remove_capability"
                              phx-value-grant-id={@direct_deny_ids[cap]}
                              class="hover:opacity-70 ml-0.5 text-danger-ink"
                              title="Remove denial"
                            >
                              ✕
                            </button>
                          </span>
                        </div>
                      </div>
                    </div>

                    <!-- Add Capabilities Picker -->
                    <div :if={@can_manage? and @grouped_available_capabilities != %{}} id="add-capabilities-section" class="border-t border-line pt-3">
                      <div class="text-[11px] font-semibold uppercase tracking-wider text-ink-subtle mb-2">Add Capabilities</div>
                      <input
                        type="text"
                        id="capability-search-input"
                        phx-input="search_capabilities"
                        placeholder="Search capabilities..."
                        value={@capability_search}
                        class="w-full rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none mb-2"
                      />
                      <form phx-change="select_capabilities" phx-submit="add_selected_capabilities" id="add-capabilities-form">
                        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-1 max-h-48 overflow-y-auto" id="available-capabilities-list">
                          <%= for {_domain, caps} <- @grouped_available_capabilities, cap <- caps, String.contains?(String.downcase(cap), String.downcase(@capability_search)) do %>
                            <label
                              id={"available-cap-label-#{String.replace(cap, ".", "-")}"}
                              class="flex items-center gap-2 rounded px-2 py-1 text-xs hover:bg-surface cursor-pointer text-ink"
                            >
                              <input
                                type="checkbox"
                                name="capability_keys[]"
                                value={cap}
                                checked={cap in @selected_capability_keys}
                                class="rounded border-line text-action focus:ring-action"
                              />
                              <span class="truncate" title={cap}>{cap}</span>
                            </label>
                          <% end %>
                        </div>
                        <div :if={@selected_capability_keys != []} class="mt-2">
                          <.button type="submit" variant="primary" id="confirm-add-capabilities-btn" class="text-xs">
                            Add ({length(@selected_capability_keys)})
                          </.button>
                        </div>
                      </form>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </.card>

          <!-- Card 3: Change Password -->
          <.card id="user-password-card">
            <div class="p-4">
              <button
                type="button"
                id="toggle-change-password-btn"
                phx-click="toggle_change_password"
                class="flex w-full items-center justify-between text-left text-xs font-semibold uppercase tracking-wider text-ink-subtle hover:text-ink"
              >
                <span>Change Password</span>
                <.icon name={if @show_change_password, do: "hero-chevron-up", else: "hero-chevron-down"} class="size-4" />
              </button>

              <div :if={@show_change_password} id="change-password-form-container" class="mt-4 max-w-md">
                <.form
                  for={@password_form}
                  id="user-password-form"
                  phx-submit="update_password"
                  class="space-y-4"
                >
                  <div>
                    <label for="user-new-password" class="block text-xs font-medium text-ink">New Password</label>
                    <input
                      type="password"
                      name="password"
                      id="user-new-password"
                      required
                      autocomplete="new-password"
                      placeholder="Enter new password"
                      class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                    />
                    <p :if={@password_errors[:password]} class="mt-1 text-xs text-danger-ink">{@password_errors[:password]}</p>
                  </div>

                  <div>
                    <label for="user-new-password-confirmation" class="block text-xs font-medium text-ink">Confirm New Password</label>
                    <input
                      type="password"
                      name="password_confirmation"
                      id="user-new-password-confirmation"
                      required
                      autocomplete="new-password"
                      placeholder="Confirm new password"
                      class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                    />
                    <p :if={@password_errors[:password_confirmation]} class="mt-1 text-xs text-danger-ink">{@password_errors[:password_confirmation]}</p>
                  </div>

                  <.button type="submit" variant="primary" id="update-password-btn" class="text-xs">
                    Update Password
                  </.button>
                </.form>
              </div>
            </div>
          </.card>

          <!-- Card 4: Employee Records -->
          <.card id="user-employees-card">
            <div class="p-4 space-y-4">
              <div class="flex items-center justify-between border-b border-line pb-2">
                <div>
                  <div class="flex items-center gap-2">
                    <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">Employee Records</h3>
                    <span id="employees-count"><.badge kind={:neutral}>{length(@employees)}</.badge></span>
                  </div>
                  <p class="mt-0.5 text-xs text-ink-muted">
                    Employment records linking this user to companies. A user can have multiple records across different companies (e.g. contractors). Not all employees require a user account.
                  </p>
                </div>
                <div :if={@can_manage? and not is_nil(@user.company_id)}>
                  <.button
                    type="button"
                    id="open-add-employee-modal-btn"
                    phx-click="open_add_employee_modal"
                    variant="primary"
                    class="text-xs"
                  >
                    + Add Employee
                  </.button>
                </div>
              </div>

              <.table
                id="user-employees-table"
                rows={@sorted_employees}
                sort_by={@employees_sort_by}
                sort_dir={@employees_sort_dir}
                sort_event="sort_employees"
              >
                <:col :let={emp} label="Employee No." sort="employee_number">
                  <.link navigate={~p"/employees/#{emp.id}"} class="text-action hover:underline font-medium">
                    {emp.employee_number || "—"}
                  </.link>
                </:col>
                <:col :let={emp} label="Company" sort="company">
                  {Map.get(@company_names, emp.company_id, "—")}
                </:col>
                <:col :let={emp} label="Designation" sort="designation">
                  {emp.designation || "—"}
                </:col>
                <:col :let={emp} label="Status" sort="status">
                  <.badge kind={employee_status_kind(emp.status)}>
                    {emp.status || "active"}
                  </.badge>
                </:col>
                <:col :let={emp} label="Employment Start" sort="employment_start">
                  <.datetime id={"employee-start-#{emp.id}"} :if={emp.employment_start} value={emp.employment_start} />
                  <span :if={is_nil(emp.employment_start)} class="text-ink-faint">—</span>
                </:col>
                <:action :let={emp}>
                  <.button
                    :if={@can_manage?}
                    type="button"
                    id={"unlink-employee-#{emp.id}"}
                    phx-click="unlink_employee"
                    phx-value-employee-id={emp.id}
                    data-confirm="Unlink this employee record from the user?"
                    class="text-xs text-danger-ink hover:text-danger"
                  >
                    Unlink
                  </.button>
                </:action>
                <:empty :if={@employees == []}>
                  No employee records.
                </:empty>
              </.table>

              <!-- Link Existing Employee Form -->
              <div :if={@can_manage? and @unlinkable_employees != []} id="link-employee-section" class="border-t border-line pt-3">
                <div :if={not @show_link_employee}>
                  <.button
                    type="button"
                    id="toggle-link-employee-btn"
                    phx-click="toggle_link_employee"
                    class="text-xs"
                  >
                    + Link Employee
                  </.button>
                </div>
                <div :if={@show_link_employee} class="flex items-center gap-2" id="link-employee-form-container">
                  <form phx-submit="link_employee" id="link-employee-form" class="flex items-center gap-2">
                    <select
                      name="employee_id"
                      id="link-employee-select"
                      class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none"
                    >
                      <option value="">Select an employee...</option>
                      <option
                        :for={emp <- @unlinkable_employees}
                        value={emp.id}
                      >
                        {emp.full_name} ({emp.employee_number})
                      </option>
                    </select>
                    <.button type="submit" variant="primary" id="confirm-link-employee-btn" class="text-xs">
                      Link
                    </.button>
                    <.button type="button" phx-click="toggle_link_employee" class="text-xs">
                      Cancel
                    </.button>
                  </form>
                </div>
              </div>
            </div>
          </.card>

          <!-- Card 5: External Accesses -->
          <.card id="user-external-accesses-card">
            <div class="p-4 space-y-4">
              <div class="border-b border-line pb-2">
                <div class="flex items-center gap-2">
                  <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">External Accesses</h3>
                  <span id="external-accesses-count"><.badge kind={:neutral}>{length(@external_accesses)}</.badge></span>
                </div>
                <p class="mt-0.5 text-xs text-ink-muted">
                  Portal access granted to this user by other companies. Allows customers or suppliers to view shared data.
                </p>
              </div>

              <.table
                id="user-external-accesses-table"
                rows={@sorted_external_accesses}
                sort_by={@external_accesses_sort_by}
                sort_dir={@external_accesses_sort_dir}
                sort_event="sort_external_accesses"
              >
                <:col :let={access} label="Granting Company" sort="company">
                  {Map.get(@company_names, access.company_id, "—")}
                </:col>
                <:col :let={access} label="Permissions" sort="permissions">
                  <%= if is_list(access.permissions) and access.permissions != [] do %>
                    <div class="flex flex-wrap gap-1">
                      <span :for={p <- access.permissions} class="inline-flex rounded bg-surface-muted px-1.5 py-0.5 text-[11px] text-ink">
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
                  <.datetime id={"access-granted-#{access.id}"} :if={access.access_granted_at} value={access.access_granted_at} />
                  <span :if={is_nil(access.access_granted_at)} class="text-ink-faint">—</span>
                </:col>
                <:col :let={access} label="Expires At" sort="expires_at">
                  <.datetime id={"access-expires-#{access.id}"} :if={access.access_expires_at} value={access.access_expires_at} />
                  <span :if={is_nil(access.access_expires_at)} class="text-ink-faint">—</span>
                </:col>
                <:empty :if={@external_accesses == []}>
                  No external accesses.
                </:empty>
              </.table>
            </div>
          </.card>

          <!-- Card 6: Danger Zone (Delete Account) -->
          <section :if={allowed?(@current_scope, "admin.user.delete")} id="user-danger" class="rounded-xl border border-danger-line bg-danger-surface px-5 py-4">
            <div class="flex items-center justify-between gap-4">
              <div>
                <h2 class="text-sm font-semibold text-danger-ink">Delete this user</h2>
                <p class="mt-0.5 text-xs text-danger-ink">Permanently deletes this account. This cannot be undone.</p>
              </div>
              <.button id="user-delete" phx-click="delete" data-confirm={"Delete #{@user.name}? This cannot be undone."} class="border-danger bg-danger text-sm font-medium text-action-ink hover:opacity-90">
                Delete user
              </.button>
            </div>
          </section>
        </div>

        <!-- Add Employee Modal Dialog -->
        <div
          :if={@show_add_employee_modal}
          id="add-employee-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              Add Employee Record
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              Create a new employee record and link it to this user.
            </p>

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
                  class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                >
                  <option
                    :for={company <- @companies}
                    value={company.id}
                    selected={@new_employee_form[:company_id].value == company.id}
                  >
                    {Company.Summary.display_name(company)}
                  </option>
                </select>
                <p :if={@new_employee_errors[:company_id]} class="mt-1 text-xs text-danger-ink">{@new_employee_errors[:company_id]}</p>
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
                    class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                  <p :if={@new_employee_errors[:employee_number]} class="mt-1 text-xs text-danger-ink">{@new_employee_errors[:employee_number]}</p>
                </div>
                <div>
                  <label for="new-emp-name" class="block text-xs font-medium text-ink">Full Name</label>
                  <input
                    type="text"
                    name="full_name"
                    id="new-emp-name"
                    required
                    value={@new_employee_form[:full_name].value}
                    class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                  <p :if={@new_employee_errors[:full_name]} class="mt-1 text-xs text-danger-ink">{@new_employee_errors[:full_name]}</p>
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
                    class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                </div>
                <div>
                  <label for="new-emp-start" class="block text-xs font-medium text-ink">Employment Start</label>
                  <input
                    type="date"
                    name="employment_start"
                    id="new-emp-start"
                    value={@new_employee_form[:employment_start].value}
                    class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none"
                  />
                </div>
              </div>

              <div class="mt-6 flex justify-end gap-2">
                <.button type="button" phx-click="close_add_employee_modal" id="cancel-add-employee-btn" class="text-xs">
                  Cancel
                </.button>
                <.button type="submit" variant="primary" id="confirm-add-employee-btn" class="text-xs">
                  Create & Link
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </.page>
    </Layouts.app>
    """
  end

  # --- Private Helpers ---

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

  defp sort_employees(employees, column, dir, company_names) do
    employees
    |> Enum.sort_by(
      fn emp ->
        case column do
          "company" -> Map.get(company_names, emp.company_id, "")
          "department" -> emp.department_id || 0
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
end
