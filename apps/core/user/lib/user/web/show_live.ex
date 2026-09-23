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
  through. When that company is archived (soft-deleted, so
  `Company.list_companies/1` does not name it), the page reads it as an
  archived company rather than as no company at all, and the account is
  read-only: no write on it can land, because every Core User and Base Authz
  write resolves the account's company and refuses an archived one, and
  nobody can sign in as or impersonate the account for the same reason. So
  the page offers no editor, picker, password form, employee action, delete
  or Impersonate for it, and one warning under the header says why. No
  declared Company API returns an archived company's name, archiving is
  final (no restore, and no moving an account to another company), and the
  account's email stays unique platform-wide, so a replacement account
  cannot reuse it; the notice therefore names neither the company nor a
  next step, and states the finality as a rule. Hiding the controls is presentation: every write handler
  still asks Authz and then Core Company, so a forged or stale commit is
  refused on the fact or through the error flash.

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
  sections and their own affordances. Every section has the anatomy
  DESIGN.md's "Detail sections and facts" sets out: a `<.card>` region opened
  by `<.section_heading>`, whose facts — the User Details, the assigned roles
  and each domain of effective and denied permissions — are the shared
  `<.list>`. The two disclosures (Effective Permissions, Change Password)
  keep their hand-written trigger until the shared disclosure lands.
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
    |> assign(:pending_authz, nil)
    |> assign(:pending_unlink, nil)
    |> assign(:pending_delete?, false)
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

    # Effective permissions. `get_tenant_user/2` mounts no account without a
    # company, so the actor always has one to evaluate in.
    actor = Authz.actor(:user, user.id, scope, user.company_id)
    effective_keys = Enum.sort(Authz.effective_capabilities(actor).allowed)
    grouped_effective_permissions = group_by_domain(effective_keys)

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

    # `list_companies/1` names every live company of the workspace, so the
    # account's company is missing from it only when archived.
    company_name = Map.get(company_names, user.company_id)
    company_archived? = is_nil(company_name)
    can_edit? = can_manage? and not company_archived?

    roles_control =
      roles_control(
        company_archived?,
        can_manage?,
        has_grant_all?,
        all_roles,
        unassigned_roles,
        available_roles
      )

    capabilities_control =
      capabilities_control(
        company_archived?,
        can_manage?,
        Enum.reject(all_registered_caps, &MapSet.member?(excluded_keys, &1)),
        available_caps
      )

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

    # Company employees not already linked to this user
    unlinkable_employees =
      tenant_employees
      |> Enum.filter(&(&1.company_id == user.company_id and &1.id != user.employee_id))
      |> Enum.sort_by(& &1.full_name)

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
    |> assign(:company_archived?, company_archived?)
    |> assign(:can_edit?, can_edit?)
    |> assign(:companies, companies)
    |> assign(:company_names, company_names)
    |> assign(:company_name, company_name)
    |> assign(:department_names, department_names)
    |> assign(:assigned_roles, assigned_roles)
    |> assign(:assigned_role_ids, assigned_role_ids)
    |> assign(:has_grant_all?, has_grant_all?)
    |> assign(:available_roles, available_roles)
    |> assign(
      :filtered_available_roles,
      filter_roles(available_roles, socket.assigns[:role_search] || "")
    )
    |> assign(:roles_control, roles_control)
    |> assign(:can_create_roles?, allowed?(current_scope, "admin.authz.role.create"))
    |> assign(:can_list_roles?, allowed?(current_scope, "admin.authz.role.list"))
    |> assign(:direct_grant_ids, direct_grant_ids)
    |> assign(:direct_deny_ids, direct_deny_ids)
    |> assign(:effective_keys, effective_keys)
    |> assign(:grouped_effective_permissions, grouped_effective_permissions)
    |> assign(:grouped_denied_permissions, grouped_denied_permissions)
    |> assign(:grouped_available_capabilities, grouped_available_capabilities)
    |> assign(
      :filtered_available_capabilities,
      filter_capabilities(
        grouped_available_capabilities,
        socket.assigns[:capability_search] || ""
      )
    )
    |> assign(:capabilities_control, capabilities_control)
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
  # Authz and then Core Company; the `can_edit?` and `company_archived?`
  # assigns only decide what the page shows.
  @impl true
  def handle_event("save_field", params, socket) do
    with true <- can_manage?(socket),
         {:ok, name, field, value} <- CommitStatus.inline_field(params, @inline_fields) do
      if archived_company?(socket) do
        {:noreply, archived_refused(socket, name)}
      else
        {:noreply, save_fact(socket, name, %{field => value}, value)}
      end
    else
      false -> {:noreply, write_forbidden(socket)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("edit_field", %{"field" => "company"}, socket) do
    cond do
      not can_manage?(socket) -> {:noreply, write_forbidden(socket)}
      archived_company?(socket) -> {:noreply, archived_refused(socket, "company")}
      true -> {:noreply, assign(socket, :editing_field, "company")}
    end
  end

  def handle_event("edit_field", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit_field", _params, socket) do
    {:noreply, close_company_editor(socket)}
  end

  # The company choice commits on change, as Belimbing's saveCompany does.
  # Only a reassignment is offered: the select carries no choosable blank, so a
  # blank value is a forged or stale submission and is refused on the fact
  # without a write. The reassignment ends the account's sessions; the open
  # editor warned about that before the choice was made.
  def handle_event("save_company", params, socket) do
    cond do
      not can_manage?(socket) -> {:noreply, write_forbidden(socket)}
      archived_company?(socket) -> {:noreply, archived_refused(socket, "company")}
      true -> save_company(socket, params)
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
    cond do
      not can_manage?(socket) -> {:noreply, roles_forbidden(socket)}
      archived_company?(socket) -> {:noreply, archived_refused(socket)}
      true -> assign_selected_roles(socket, params)
    end
  end

  # Every authorization change on this card confirms through the shared
  # dialog. The request holds the rule the dialog names -- a role assignment, a
  # direct grant, a deny rule or a capability to deny -- and the confirm acts
  # on that held rule rather than on a client-supplied id, so what was
  # confirmed is what changes.
  def handle_event("request_remove_role", %{"assignment-id" => assignment_id_str}, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, roles_forbidden(socket)}

      archived_company?(socket) ->
        {:noreply, archived_refused(socket)}

      assignment = find_assignment(socket, assignment_id_str) ->
        hold_authz(socket, {:remove_role, assignment})

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_authz", _params, socket) do
    {:noreply, assign(socket, :pending_authz, nil)}
  end

  def handle_event("remove_role", _params, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, roles_forbidden(socket)}

      not match?({:remove_role, _}, socket.assigns.pending_authz) ->
        {:noreply, socket}

      true ->
        {:remove_role, assignment} = socket.assigns.pending_authz
        socket = assign(socket, :pending_authz, nil)
        scope = socket.assigns.current_scope.scope
        user = socket.assigns.user

        case Authz.unassign_role(scope, assignment.role_id, assignment.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:success, "The #{assignment.role_name} role was removed.")
             |> load_data(user)}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "The #{assignment.role_name} role was not removed. Reload the page and try again."
             )}
        end
    end
  end

  # --- Event Handlers: Permissions ---

  def handle_event("toggle_effective_permissions", _params, socket) do
    {:noreply,
     assign(socket, :show_effective_permissions, not socket.assigns.show_effective_permissions)}
  end

  def handle_event("search_capabilities", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:capability_search, query)
     |> assign(
       :filtered_available_capabilities,
       filter_capabilities(socket.assigns.grouped_available_capabilities, query)
     )}
  end

  def handle_event("select_capabilities", params, socket) do
    cap_keys = Map.get(params, "capability_keys", [])
    {:noreply, assign(socket, :selected_capability_keys, cap_keys)}
  end

  def handle_event("add_selected_capabilities", params, socket) do
    cond do
      not can_manage?(socket) -> capabilities_forbidden(socket)
      archived_company?(socket) -> {:noreply, archived_refused(socket)}
      true -> add_selected_capabilities(socket, params)
    end
  end

  def handle_event("request_deny_capability", %{"capability-key" => cap_key}, socket) do
    cond do
      not can_manage?(socket) ->
        capabilities_forbidden(socket)

      archived_company?(socket) ->
        {:noreply, archived_refused(socket)}

      cap_key in socket.assigns.effective_keys ->
        hold_authz(socket, {:deny, cap_key})

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("deny_capability", _params, socket) do
    cond do
      not can_manage?(socket) ->
        capabilities_forbidden(socket)

      not match?({:deny, _}, socket.assigns.pending_authz) ->
        {:noreply, socket}

      true ->
        {:deny, cap_key} = socket.assigns.pending_authz
        socket = assign(socket, :pending_authz, nil)
        scope = socket.assigns.current_scope.scope
        user = socket.assigns.user

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
             |> put_flash(:success, "#{cap_key} is denied for #{user.name}.")
             |> load_data(user)}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "#{cap_key} was not denied. Reload the page and try again."
             )}
        end
    end
  end

  # A grant id backs two controls -- a direct grant and a deny rule -- so the
  # request resolves which one it is from the page's own maps before it opens
  # a dialog, and the copy says what removing that rule does.
  def handle_event("request_remove_capability", %{"grant-id" => grant_id_str}, socket) do
    cond do
      not can_manage?(socket) -> capabilities_forbidden(socket)
      archived_company?(socket) -> {:noreply, archived_refused(socket)}
      rule = find_capability_rule(socket, grant_id_str) -> hold_authz(socket, rule)
      true -> {:noreply, socket}
    end
  end

  def handle_event("remove_capability", _params, socket) do
    cond do
      not can_manage?(socket) ->
        capabilities_forbidden(socket)

      not match?(
        {kind, _, _} when kind in [:remove_grant, :remove_denial],
        socket.assigns.pending_authz
      ) ->
        {:noreply, socket}

      true ->
        {kind, cap_key, grant_id} = socket.assigns.pending_authz
        socket = assign(socket, :pending_authz, nil)
        scope = socket.assigns.current_scope.scope
        user = socket.assigns.user

        case Authz.remove_principal_capability(scope, grant_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:success, capability_removed_message(kind, cap_key))
             |> load_data(user)}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "The rule for #{cap_key} was not removed. Reload the page and try again."
             )}
        end
    end
  end

  # --- Event Handlers: Password ---

  def handle_event("toggle_change_password", _params, socket) do
    {:noreply, assign(socket, :show_change_password, not socket.assigns.show_change_password)}
  end

  def handle_event("update_password", params, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, put_flash(socket, :error, "You do not have permission to change passwords.")}

      archived_company?(socket) ->
        {:noreply, archived_refused(socket)}

      true ->
        update_password(socket, params)
    end
  end

  # --- Event Handlers: Employee Records ---

  def handle_event("toggle_link_employee", _params, socket) do
    {:noreply, assign(socket, :show_link_employee, not socket.assigns.show_link_employee)}
  end

  def handle_event("link_employee", %{"employee_id" => employee_id_str}, socket) do
    cond do
      not can_manage?(socket) -> {:noreply, users_forbidden(socket)}
      archived_company?(socket) -> {:noreply, archived_refused(socket)}
      true -> link_employee(socket, employee_id_str)
    end
  end

  # Unlinking confirms through the shared dialog: the request holds the listed
  # employee record the dialog names, and `unlink_employee` clears the account's
  # link only once one is held.
  def handle_event("request_unlink_employee", %{"employee-id" => employee_id_str}, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, users_forbidden(socket)}

      archived_company?(socket) ->
        {:noreply, archived_refused(socket)}

      emp = find_linked_employee(socket, employee_id_str) ->
        {:noreply, socket |> clear_flash() |> assign(:pending_unlink, emp)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_unlink_employee", _params, socket) do
    {:noreply, assign(socket, :pending_unlink, nil)}
  end

  def handle_event("unlink_employee", _params, socket) do
    cond do
      not can_manage?(socket) ->
        {:noreply, users_forbidden(socket)}

      is_nil(socket.assigns.pending_unlink) ->
        {:noreply, socket}

      true ->
        emp = socket.assigns.pending_unlink
        socket = assign(socket, :pending_unlink, nil)
        scope = socket.assigns.current_scope.scope
        user = socket.assigns.user

        case User.update_user(scope, user.company_id, user.id, %{employee_id: nil}) do
          {:ok, updated_user} ->
            {:noreply,
             socket
             |> put_flash(:success, "#{emp.full_name} was unlinked from #{user.name}.")
             |> load_data(updated_user)}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "#{emp.full_name} was not unlinked. Reload the page and try again."
             )}
        end
    end
  end

  # Creating the record and linking it are two writes, and only the link is
  # refused for an archived company, so the modal is refused before it opens
  # rather than leaving an unlinked employee behind a refused link.
  def handle_event("open_add_employee_modal", _params, socket) do
    cond do
      not can_manage?(socket) -> {:noreply, users_forbidden(socket)}
      archived_company?(socket) -> {:noreply, archived_refused(socket)}
      true -> {:noreply, open_add_employee_modal(socket)}
    end
  end

  def handle_event("close_add_employee_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_employee_modal, false)}
  end

  def handle_event("save_new_employee", params, socket) do
    cond do
      not can_manage?(socket) -> {:noreply, users_forbidden(socket)}
      archived_company?(socket) -> {:noreply, archived_refused(socket)}
      true -> save_new_employee(socket, params)
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

  # Deleting confirms through the shared dialog, which states what happens to
  # this account. The signed-in account is refused before any dialog opens;
  # `delete` runs only once a request is held.
  def handle_event("request_delete", _params, socket) do
    cond do
      not allowed?(socket.assigns.current_scope, "admin.user.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete users.")}

      own_account?(socket) ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}

      archived_company?(socket) ->
        {:noreply, archived_refused(socket)}

      true ->
        {:noreply, socket |> clear_flash() |> assign(:pending_delete?, true)}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete?, false)}
  end

  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user

    cond do
      not allowed?(socket.assigns.current_scope, "admin.user.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete users.")}

      own_account?(socket) ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}

      not socket.assigns.pending_delete? ->
        {:noreply, socket}

      true ->
        socket = assign(socket, :pending_delete?, false)

        case User.delete_user(scope, user.company_id, user.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:success, "#{user.name}'s account was deleted.")
             |> push_navigate(to: ~p"/users")}

          {:error, :company_not_found} ->
            {:noreply,
             put_flash(socket, :error, "#{user.name} was not deleted: their company is archived.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "#{user.name} was not deleted. Reload the page and try again."
             )}
        end
    end
  end

  # --- Write bodies, entered only once the capability and company checks passed ---

  defp save_company(socket, params) do
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
  end

  defp assign_selected_roles(socket, params) do
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
         |> put_flash(:success, msg)
         |> assign(:selected_role_ids, [])
         |> assign(:show_assign_roles, false)
         |> load_data(user)}

      true ->
        {:noreply, socket}
    end
  end

  defp add_selected_capabilities(socket, params) do
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
         |> put_flash(:success, msg)
         |> assign(:selected_capability_keys, [])
         |> load_data(user)}

      true ->
        {:noreply, socket}
    end
  end

  defp update_password(socket, params) do
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
           |> put_flash(:success, "Password updated successfully.")
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
  end

  defp link_employee(socket, employee_id_str) do
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user

    case Integer.parse(employee_id_str) do
      {employee_id, ""} ->
        case User.update_user(scope, user.company_id, user.id, %{employee_id: employee_id}) do
          {:ok, updated_user} ->
            {:noreply,
             socket
             |> put_flash(:success, "Employee linked.")
             |> assign(:show_link_employee, false)
             |> load_data(updated_user)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to link employee.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp open_add_employee_modal(socket) do
    user = socket.assigns.user

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
    |> assign(:new_employee_errors, %{})
  end

  defp save_new_employee(socket, params) do
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
         |> put_flash(:success, "Employee created and linked.")
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
  end

  defp own_account?(socket) do
    socket.assigns.user.id == socket.assigns.current_scope.user["user_id"]
  end

  # --- Confirmation helpers ---

  defp hold_authz(socket, rule) do
    {:noreply, socket |> clear_flash() |> assign(:pending_authz, rule)}
  end

  defp capabilities_forbidden(socket) do
    {:noreply, put_flash(socket, :error, "You do not have permission to manage capabilities.")}
  end

  defp roles_forbidden(socket),
    do: put_flash(socket, :error, "You do not have permission to manage roles.")

  defp users_forbidden(socket),
    do: put_flash(socket, :error, "You do not have permission to edit users.")

  # A write on an archived-company account is refused where the page reports
  # that write: on the fact that asked, or through the error flash. Either
  # way a stale "Saved" is dropped, as for a forbidden write.
  defp archived_refused(socket, name),
    do: CommitStatus.put(socket, name, {:error, archived_company_message()})

  defp archived_refused(socket),
    do: CommitStatus.write_forbidden(socket, archived_account_message())

  defp find_assignment(socket, assignment_id_str) do
    case Integer.parse(assignment_id_str) do
      {id, ""} -> Enum.find(socket.assigns.assigned_roles, &(&1.id == id))
      _ -> nil
    end
  end

  defp find_capability_rule(socket, grant_id_str) do
    case Integer.parse(grant_id_str) do
      {grant_id, ""} ->
        grants = socket.assigns.direct_grant_ids
        denials = socket.assigns.direct_deny_ids

        case {Enum.find(grants, &match?({_cap, ^grant_id}, &1)),
              Enum.find(denials, &match?({_cap, ^grant_id}, &1))} do
          {{cap, _id}, _} -> {:remove_grant, cap, grant_id}
          {_, {cap, _id}} -> {:remove_denial, cap, grant_id}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp find_linked_employee(socket, employee_id_str) do
    case Integer.parse(employee_id_str) do
      {id, ""} -> Enum.find(socket.assigns.employees, &(&1.id == id))
      _ -> nil
    end
  end

  defp capability_removed_message(:remove_grant, cap_key),
    do: "The direct grant of #{cap_key} was removed."

  defp capability_removed_message(:remove_denial, cap_key),
    do: "The deny rule for #{cap_key} was removed."

  # The dialog states what the held rule does to this person's access.
  defp authz_consequence({:remove_role, assignment}, user),
    do: "The #{assignment.role_name} role will be removed from #{user.name}."

  defp authz_consequence({:deny, cap_key}, user),
    do: "#{cap_key} will be denied for #{user.name}."

  defp authz_consequence({:remove_grant, cap_key, _id}, user),
    do: "The direct grant of #{cap_key} will be removed from #{user.name}."

  defp authz_consequence({:remove_denial, cap_key, _id}, _user),
    do: "The deny rule for #{cap_key} will be removed."

  defp authz_detail({:remove_role, _assignment}, _user),
    do:
      "They lose every capability this role grants unless another role or direct grant " <>
        "also provides it. The role can be assigned again."

  defp authz_detail({:deny, _cap_key}, _user),
    do:
      "The deny rule overrides every role that grants it and takes effect at once. " <>
        "It can be removed again from the denied list."

  defp authz_detail({:remove_grant, _cap_key, _id}, _user),
    do:
      "They keep this capability only if an assigned role still grants it. " <>
        "The grant can be added again."

  defp authz_detail({:remove_denial, _cap_key, _id}, user),
    do: "#{user.name} regains this capability from any role or direct grant that provides it."

  defp authz_verb({:deny, _cap_key}), do: "Deny"
  defp authz_verb(_rule), do: "Remove"
  defp authz_working({:deny, _cap_key}), do: "Denying…"
  defp authz_working(_rule), do: "Removing…"
  defp authz_event({:remove_role, _assignment}), do: "remove_role"
  defp authz_event({:deny, _cap_key}), do: "deny_capability"
  defp authz_event(_rule), do: "remove_capability"

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
                opts={%{auditable_types: user_auditable_types(), auditable_id: @user.id, record: @user}}
              />
              <.action_link
                :if={can_impersonate?(@current_scope, @user, @company_archived?)}
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

        <%!-- The one place the page says why it is read-only, before the
             reader reaches a fact. It names the condition and what it
             prevents, and states that archiving is final. --%>
        <.alert :if={@company_archived?} id="user-archived-company" kind={:warning}>
          {archived_account_notice(@user)}
        </.alert>

        <div class="mt-6 space-y-6">
          <%!-- Section 1: User Details. The facts are the shared `<.list>`
               under the shared `<.section_heading>`, as on `/companies/:id`,
               `/addresses/:id` and `/employees/:id`; each fact edits in place
               and reports on itself, so the heading carries no button. --%>
          <.card
            id="user-details-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="user-details-heading"
          >
            <.section_heading id="user-details-heading" title="User Details" />

            <.list id="user-details">
              <:item title={fact_label("name")} id="user-view-name">
                <.text_fact
                  name="name"
                  user={@user}
                  editable?={@can_edit?}
                  field_status={@field_status}
                />
              </:item>
              <:item title={fact_label("email")} id="user-view-email">
                <.text_fact
                  name="email"
                  user={@user}
                  editable?={@can_edit?}
                  field_status={@field_status}
                />
              </:item>
              <:item title="Company" id="user-view-company">
                <button
                  :if={@can_edit? and @editing_field != "company"}
                  type="button"
                  id="user-company-display"
                  phx-click="edit_field"
                  phx-value-field="company"
                  aria-label="Edit company"
                  aria-describedby={@field_status["company"] && "user-company-status"}
                  class="group -mx-1.5 flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 text-left transition-colors hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
                >
                  <span class="text-ink">{@company_name}</span>
                  <.icon
                    name="edit"
                    class="size-3.5 shrink-0 text-ink-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
                  />
                </button>

                <%!-- Window-scoped: the select may not hold focus (JS.focus is
                     best-effort), and Escape must cancel regardless. Only one
                     editor mounts at a time, so the listener is unambiguous. --%>
                <div
                  :if={@can_edit? and @editing_field == "company"}
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

                <%!-- Read-only: a viewer's live company links to its page; an
                     archived company has no page to reach and no name the
                     Company API returns. --%>
                <%= if not @can_edit? do %>
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
              </:item>
              <:item title="Email Verified" id="user-view-email-verified">
                <.badge kind={if @user.email_verified_at, do: :success, else: :warning}>
                  <%= if @user.email_verified_at do %>
                    <.datetime id="user-email-verified-at" value={@user.email_verified_at} />
                  <% else %>
                    unverified
                  <% end %>
                </.badge>
              </:item>
              <:item title="Created" id="user-view-created">
                <span class="text-ink-muted tabular-nums">
                  <.datetime :if={@user.created_at} id="user-created-at" value={@user.created_at} />
                  <span :if={is_nil(@user.created_at)} class="text-ink-faint">—</span>
                </span>
              </:item>
              <:item title="Updated" id="user-view-updated">
                <span class="text-ink-muted tabular-nums">
                  <.datetime :if={@user.updated_at} id="user-updated-at" value={@user.updated_at} />
                  <span :if={is_nil(@user.updated_at)} class="text-ink-faint">—</span>
                </span>
              </:item>
            </.list>
          </.card>

          <%!-- Section 2: Roles & Permissions. Roles are a fact of the shared
               list; the pickers and the effective-permission disclosure keep
               their own controls below it. --%>
          <.card
            id="user-roles-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="user-roles-heading"
          >
            <.section_heading
              id="user-roles-heading"
              title="Roles & Permissions"
              count={length(@assigned_roles)}
            >
              <:description>
                Roles determine what this user can do. Each role grants a set of capabilities. Effective permissions show the combined result of all assigned roles.
              </:description>
            </.section_heading>

            <div class="mb-4">
              <.list id="assigned-roles-container">
                <:item title="Roles" id="assigned-roles">
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
                          :if={@can_edit?}
                          icon="close"
                          label={"Remove the #{assignment.role_name} role"}
                          context={:inline}
                          kind={:danger}
                          id={"remove-role-#{assignment.id}"}
                          phx-click="request_remove_role"
                          phx-value-assignment-id={assignment.id}
                          class="-mr-1"
                        />
                      </span>
                    </div>
                  <% end %>
                </:item>
              </.list>
            </div>

            <%!-- The Roles control, or the one sentence that says why it is absent.
                 The sentence stands where the control would be, so a reader who
                 finds no button is not left wondering; it names the most
                 actionable condition (permission first, then whether a role
                 could add anything, then the roles themselves). --%>
            <%= if @roles_control == :available do %>
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
                  <form phx-change="search_roles" phx-submit="search_roles" id="role-search-form">
                    <label for="role-search-input" class="sr-only">Search roles</label>
                    <input
                      type="search"
                      id="role-search-input"
                      name="value"
                      phx-debounce="300"
                      autocomplete="off"
                      placeholder="Search roles..."
                      value={@role_search}
                      class="w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none"
                    />
                  </form>
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
                    <.empty_state
                      :if={@filtered_available_roles == []}
                      id="available-roles-empty"
                      class="py-2"
                      title={"No roles match “#{String.trim(@role_search)}”"}
                      reason="Roles are matched by name. Clear the search to see every role you can assign."
                    />
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
            <% else %>
              <div id="assign-roles-unavailable" class="mb-6">
                <%= case @roles_control do %>
                  <% :archived -> %>
                    <.empty_state
                      title="Roles can't be changed"
                      reason="This user's company is archived, so no role can be assigned or removed."
                    />
                  <% :forbidden -> %>
                    <.empty_state forbidden={"assign roles to this user, which needs #{manage_capability()}"} />
                  <% :grant_all -> %>
                    <.empty_state
                      title="A role would add nothing"
                      reason={"#{grant_all_role_names(@assigned_roles)} already grants every capability, so this user holds everything a role could add."}
                    />
                  <% :no_roles -> %>
                    <.empty_state
                      title="No roles exist yet"
                      reason={no_roles_reason(@can_create_roles?)}
                    >
                      <:action :if={@can_create_roles?}>
                        <.action_link
                          id="assign-roles-create-link"
                          icon="create"
                          navigate={~p"/authz/roles/create"}
                          title="Create a role"
                        >
                          Create a role
                        </.action_link>
                      </:action>
                      <:action :if={not @can_create_roles? and @can_list_roles?}>
                        <.action_link
                          id="assign-roles-index-link"
                          icon="manage"
                          navigate={~p"/authz/roles"}
                          title="Open the Roles page"
                        >
                          Roles
                        </.action_link>
                      </:action>
                    </.empty_state>
                  <% :all_assigned -> %>
                    <.empty_state
                      title="No roles left to assign"
                      reason="This user already holds every role that exists in this workspace."
                    />
                  <% :none_grantable -> %>
                    <.empty_state
                      title="No roles your account can assign"
                      reason="Assigning a role needs every capability it grants, and each remaining role grants one your account does not hold. Ask an operator to review your role."
                    />
                <% end %>
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
                  <.list id="effective-permissions-list">
                    <:item
                      :for={{domain, caps} <- @grouped_effective_permissions}
                      title={domain}
                      id={"permissions-domain-#{domain}"}
                    >
                      <div class="flex flex-wrap gap-1">
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
                            <%= if @can_edit? do %>
                              <%= if is_direct do %>
                                <.icon_button
                                  icon="close"
                                  label={"Remove the direct grant of #{cap}"}
                                  context={:inline}
                                  kind={:danger}
                                  id={"remove-direct-cap-#{String.replace(cap, ".", "-")}"}
                                  phx-click="request_remove_capability"
                                  phx-value-grant-id={@direct_grant_ids[cap]}
                                />
                              <% else %>
                                <.icon_button
                                  icon="close"
                                  label={"Deny #{cap}"}
                                  context={:inline}
                                  kind={:danger}
                                  id={"deny-cap-#{String.replace(cap, ".", "-")}"}
                                  phx-click="request_deny_capability"
                                  phx-value-capability-key={cap}
                                />
                              <% end %>
                            <% end %>
                          </span>
                        <% end %>
                      </div>
                    </:item>
                  </.list>
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
                  <.list id="denied-permissions-list">
                    <:item
                      :for={{domain, caps} <- @grouped_denied_permissions}
                      title={domain}
                      id={"denied-domain-#{domain}"}
                    >
                      <div class="flex flex-wrap gap-1">
                        <span
                          :for={cap <- caps}
                          id={"denied-cap-badge-#{String.replace(cap, ".", "-")}"}
                          class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium border border-danger-line bg-danger-surface text-danger-ink"
                        >
                          <span>{cap}</span>
                          <.icon_button
                            :if={@can_edit?}
                            icon="close"
                            label={"Remove the deny rule for #{cap}"}
                            context={:inline}
                            kind={:danger}
                            id={"remove-denial-#{String.replace(cap, ".", "-")}"}
                            phx-click="request_remove_capability"
                            phx-value-grant-id={@direct_deny_ids[cap]}
                          />
                        </span>
                      </div>
                    </:item>
                  </.list>
                </div>

                <!-- Add Capabilities Picker -->
                <div
                  :if={@capabilities_control == :available}
                  id="add-capabilities-section"
                  class="mt-4 pt-4 border-t border-line"
                >
                  <div class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle mb-2">
                    Add Capabilities
                  </div>
                  <form
                    phx-change="search_capabilities"
                    phx-submit="search_capabilities"
                    id="capability-search-form"
                    class="mb-2"
                  >
                    <label for="capability-search-input" class="sr-only">Search capabilities</label>
                    <input
                      type="search"
                      id="capability-search-input"
                      name="value"
                      phx-debounce="300"
                      autocomplete="off"
                      placeholder="Search capabilities..."
                      value={@capability_search}
                      class="w-full rounded-md border border-high-contrast-line bg-surface px-3 py-1.5 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none"
                    />
                  </form>
                  <form
                    phx-change="select_capabilities"
                    phx-submit="add_selected_capabilities"
                    id="add-capabilities-form"
                  >
                    <div
                      class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-1 max-h-48 overflow-y-auto"
                      id="available-capabilities-list"
                    >
                      <%= for {_domain, caps} <- @filtered_available_capabilities, cap <- caps do %>
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
                    <.empty_state
                      :if={@filtered_available_capabilities == %{}}
                      id="available-capabilities-empty"
                      class="py-2"
                      title={"No capabilities match “#{String.trim(@capability_search)}”"}
                      reason="Capabilities are matched by key, which starts with the domain (such as admin.). Clear the search to see every capability you can add."
                    />
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
                <%!-- The same rule as the Roles control: a hidden picker states
                     its own reason where the picker would be. --%>
                <div
                  :if={@capabilities_control != :available}
                  id="add-capabilities-unavailable"
                  class="mt-4 pt-4 border-t border-line"
                >
                  <%= case @capabilities_control do %>
                    <% :archived -> %>
                      <.empty_state
                        title="Capabilities can't be changed"
                        reason="This user's company is archived, so no capability can be added, denied or removed."
                      />
                    <% :forbidden -> %>
                      <.empty_state forbidden={"add capabilities to this user, which needs #{manage_capability()}"} />
                    <% :all_in_effect -> %>
                      <.empty_state
                        title="No capabilities left to add"
                        reason="Every installed capability is already in effect or denied for this user."
                      />
                    <% :none_grantable -> %>
                      <.empty_state
                        title="No capabilities your account can add"
                        reason="You can only add capabilities you hold, and every remaining capability is one your account does not. Ask an operator to review your role."
                      />
                  <% end %>
                </div>
              </div>
            </div>
          </.card>

          <%!-- Card 3: Change Password. The card holds nothing but the form,
               so an archived-company account, whose password cannot be
               changed, has no card; the notice under the header says so. --%>
          <.card :if={not @company_archived?} id="user-password-card" inner_class="p-5 sm:p-6">
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

          <%!-- Section 4: Employee Records --%>
          <.card
            id="user-employees-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="user-employees-heading"
          >
            <.section_heading
              id="user-employees-heading"
              title="Employee Records"
              count={length(@employees)}
            >
              <:description>
                Employment records linking this user to companies. A user can have multiple records across different companies (e.g. contractors). Not all employees require a user account.
              </:description>
              <:actions :if={@can_edit?}>
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
              </:actions>
            </.section_heading>

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
                  :if={@can_edit?}
                  icon="unlink"
                  label={"Unlink #{emp.full_name}"}
                  kind={:danger}
                  id={"unlink-employee-#{emp.id}"}
                  phx-click="request_unlink_employee"
                  phx-value-employee-id={emp.id}
                />
              </:action>
              <:empty :if={@employees == []}>
                No employee records.
              </:empty>
            </.table>

            <!-- Link Existing Employee Form -->
            <div
              :if={@can_edit? and @unlinkable_employees != []}
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

          <%!-- Section 5: External Accesses --%>
          <.card
            id="user-external-accesses-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="user-external-accesses-heading"
          >
            <.section_heading
              id="user-external-accesses-heading"
              title="External Accesses"
              count={length(@external_accesses)}
            >
              <:description>
                Portal access granted to this user by other companies. Allows customers or suppliers to view orders, invoices, and other shared data.
              </:description>
            </.section_heading>

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

          <%!-- Card 6: Danger Zone (Delete Account). Deleting an archived-company
               account is refused, so the zone is not offered for one. --%>
          <section
            :if={allowed?(@current_scope, "admin.user.delete") and not @company_archived?}
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
              <.button id="user-delete" variant="danger" phx-click="request_delete">
                Delete user
              </.button>
            </div>
          </section>
        </div>

        <.confirm_dialog
          :if={@pending_authz}
          id="user-authz-confirm"
          consequence={authz_consequence(@pending_authz, @user)}
          detail={authz_detail(@pending_authz, @user)}
          confirm={authz_verb(@pending_authz)}
          working={authz_working(@pending_authz)}
          on_confirm={JS.push(authz_event(@pending_authz))}
          on_cancel={JS.push("cancel_authz")}
        />

        <.confirm_dialog
          :if={@pending_unlink}
          id="unlink-employee-confirm"
          consequence={"#{@pending_unlink.full_name} will be unlinked from #{@user.name}."}
          detail="The employee record is kept and can be linked again."
          confirm="Unlink"
          working="Unlinking…"
          on_confirm={JS.push("unlink_employee")}
          on_cancel={JS.push("cancel_unlink_employee")}
        />

        <.confirm_dialog
          :if={@pending_delete?}
          id="delete-user-confirm"
          consequence={"#{@user.name}'s account will be deleted."}
          detail="They can no longer sign in. This cannot be undone."
          confirm="Delete"
          working="Deleting…"
          on_confirm={JS.push("delete")}
          on_cancel={JS.push("cancel_delete")}
        />

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
  # anyone else — a viewer, or any actor while the account's company is
  # archived — sees the stored value with no affordance. Name and email are
  # required columns, so an emptied input is not a commit.
  attr(:name, :string, required: true)
  attr(:user, :map, required: true)
  attr(:editable?, :boolean, required: true)
  attr(:field_status, :map, required: true)

  defp text_fact(assigns) do
    assigns =
      assigns
      |> assign(:label, fact_label(assigns.name))
      |> assign(:value, Map.fetch!(assigns.user, Map.fetch!(@inline_fields, assigns.name)))

    ~H"""
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
    <%!-- The read-only fact keeps its outlet, so a forged or stale commit
         on it is refused where the page reports facts. --%>
    <span :if={not @editable?}>{@value}</span>
    <.commit_status :if={not @editable?} id={"user-#{@name}-status"} status={@field_status[@name]} />
    """
  end

  # --- Private Helpers ---

  # The guard is the users list's: the capability, never the signed-in
  # account, never while already impersonating, and never an archived-company
  # account, whose session the host cannot open (`UserAuth.impersonate_user/3`
  # resolves the tenant through the live company and refuses it).
  defp can_impersonate?(current_scope, user, company_archived?) do
    allowed?(current_scope, "admin.user.impersonate") and
      user.id != current_scope.user["user_id"] and
      is_nil(current_scope.impersonator) and
      not company_archived?
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

      {:error, :company_not_found} when is_nil(socket.assigns.company_name) ->
        CommitStatus.put(socket, name, {:error, archived_company_message()})

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
  # An archived current company refuses every write on the account, so it is
  # the cause whatever the rule reported.
  defp company_failure_message(_reason, choice, nil),
    do: "#{inspect(choice)} was not saved: this user's company is archived."

  defp company_failure_message(:unauthorized, choice, company_name),
    do: "#{inspect(choice)} was not saved: you may not manage users of #{company_name}."

  defp company_failure_message(:company_not_found, choice, _company_name),
    do: "#{inspect(choice)} was not saved: that company is not in this workspace."

  defp company_failure_message(reason, _choice, _company_name),
    do: failure_message(reason)

  # The account's own company is archived, so no write on it can land; the
  # refusal names that company rather than the value the operator submitted.
  defp archived_company_message,
    do: "The change was not saved: this user's company is archived."

  # The same refusal through the flash, for a write that reports there.
  defp archived_account_message,
    do: "This user's company is archived, so the account can't be changed."

  # What the warning under the header says: the condition, that it is final,
  # and what it prevents on this page and beyond it. No declared Company API
  # names an archived company, archiving is never undone, and the account's
  # email stays taken platform-wide, so the notice neither names the company
  # nor offers a next step.
  defp archived_account_notice(user) do
    "#{user.name}'s company is archived, and archiving is final, so this account is " <>
      "read-only: its details, roles, permissions, password and employee links can't " <>
      "be changed, and nobody can sign in as or impersonate this user."
  end

  # The select offers no choosable blank; a blank that still arrives is refused
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

  # Why the Roles control is absent, as one reason in the order a reader can
  # act on it: an archived company refuses every grant whatever the reader
  # holds; without permission nothing else matters; a grant-all role leaves
  # nothing to add; and only then do the roles themselves decide (none exist,
  # all held, or none this account may grant under the escalation guard).
  # `:available` shows the control. A user without a company is not a case:
  # a role is granted within a company, but `get_tenant_user/2` refuses such
  # an account and mount redirects, so this page never renders one.
  # Presentation only: every write asks Authz and Core Company again.
  defp roles_control(
         archived?,
         can_manage?,
         has_grant_all?,
         all_roles,
         unassigned_roles,
         available
       ) do
    cond do
      archived? -> :archived
      not can_manage? -> :forbidden
      has_grant_all? -> :grant_all
      all_roles == [] -> :no_roles
      unassigned_roles == [] -> :all_assigned
      available == [] -> :none_grantable
      true -> :available
    end
  end

  # The same decision for the Add Capabilities picker. `remaining` is every
  # installed capability not yet in effect or denied for the user; `available`
  # is the part of it the acting account holds and may therefore grant.
  defp capabilities_control(archived?, can_manage?, remaining, available) do
    cond do
      archived? -> :archived
      not can_manage? -> :forbidden
      remaining == [] -> :all_in_effect
      available == [] -> :none_grantable
      true -> :available
    end
  end

  defp grant_all_role_names(assigned_roles) do
    assigned_roles
    |> Enum.filter(& &1.role_grant_all)
    |> Enum.map_join(" and ", & &1.role_name)
  end

  defp no_roles_reason(true),
    do: "Create one on the Roles page, then assign it here."

  defp no_roles_reason(false),
    do:
      "Roles are created on the Roles page, which needs admin.authz.role.create; your account does not hold it."

  defp manage_capability, do: @manage_capability

  # Keeps the domain grouping and drops a domain whose capabilities all fall
  # out, so the picker's empty state is decided by one comparison with `%{}`.
  defp filter_capabilities(grouped, query) do
    q = String.downcase(String.trim(query))

    if q == "" do
      grouped
    else
      grouped
      |> Enum.flat_map(fn {domain, caps} ->
        case Enum.filter(caps, &String.contains?(String.downcase(&1), q)) do
          [] -> []
          matched -> [{domain, matched}]
        end
      end)
      |> Map.new()
    end
  end

  # The mount-time assign hides controls; it is presentation state. Every
  # write asks again, because a LiveView process outlives its mount and a
  # revoked grant must not keep working until remount (#609, the #482/#541
  # pattern).
  defp can_manage?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @manage_capability).allowed
  end

  # The same freshness for the account's company: the mount-time
  # `company_archived?` assign hides the controls, and each write asks Core
  # Company again, so a company archived after mount is refused and one
  # restored after mount is written to. The domain refuses either way; this
  # check only lets the page report the refusal in its own words before a
  # dialog opens or a second write (creating an employee to link) lands.
  defp archived_company?(socket) do
    scope = socket.assigns.current_scope.scope
    match?({:error, :not_found}, Company.get_company(scope, socket.assigns.user.company_id))
  end
end
