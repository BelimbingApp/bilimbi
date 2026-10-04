defmodule Bilimbi.Core.User.Web.UserAccessPanel do
  @moduledoc """
  Roles and direct capabilities for one user, on that user's page.

  The page passes the account, the signed-in scope, and whether the
  account's company is archived. This panel loads the Authz reads in
  `update/2`, so a later change to the account reaches a fresh grant
  list. Mount-time `can_edit?` only decides which controls render.
  Every write asks Authz and Core Company again.

  Outcomes use the page flash. A LiveComponent's own `put_flash/3` does
  not reach `Layouts.app`, so a completed write or a refusal sends the
  message to the page. Opening a confirmation clears that flash first,
  with an untargeted `lv:clear-flash`, because the page behind the dialog
  is inert.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.Company

  @manage_capability "admin.user.update"

  # These toggles only flip section-visibility assigns. The persisting
  # events behind them carry their own capability check.
  @write_guard_opt_out ~w(toggle_assign_roles toggle_effective_permissions)

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_assign_roles, false)
     |> assign(:role_search, "")
     |> assign(:selected_role_ids, [])
     |> assign(:show_effective_permissions, false)
     |> assign(:capability_search, "")
     |> assign(:selected_capability_keys, [])
     |> assign(:pending_authz, nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> load_access()}
  end

  # A LiveComponent flash never reaches the page layout. The page renders
  # `Layouts.app`'s flash group, and these messages are how a write reports
  # there.
  defp page_flash(socket, kind, message) when kind in [:success, :error] and is_binary(message) do
    send(self(), {__MODULE__, :flash, kind, message})
    socket
  end

  defp page_clear_flash(socket) do
    send(self(), {__MODULE__, :clear_flash})
    socket
  end

  defp load_access(socket) do
    scope = socket.assigns.current_scope.scope
    current_scope = socket.assigns.current_scope
    user = socket.assigns.user
    company_archived? = socket.assigns.company_archived?
    can_manage? = allowed?(current_scope, @manage_capability)
    can_edit? = can_manage? and not company_archived?

    role_page = Authz.list_principal_role_assignments(scope, :user, user.id, page_size: 100)
    assigned_roles = role_page.entries
    assigned_role_ids = Enum.map(assigned_roles, & &1.role_id)

    {acting_grant_all?, acting_allowed_caps} = acting_permissions(current_scope)
    acting_allowed_set = MapSet.new(acting_allowed_caps)

    all_roles = Authz.list_roles(scope)
    unassigned_roles = Enum.reject(all_roles, &(&1.id in assigned_role_ids))

    available_roles =
      unassigned_roles
      |> grantable_roles(scope, acting_grant_all?, acting_allowed_set)

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

    # `get_tenant_user/2` mounts no account without a company, so the actor
    # always has one to evaluate in.
    actor = Authz.actor(:user, user.id, scope, user.company_id)

    %{allowed: allowed, grant_all: has_grant_all?} =
      Authz.effective_capabilities(actor)

    effective_keys = Enum.sort(allowed)
    grouped_effective_permissions = group_by_domain(effective_keys)

    denied_keys = Map.keys(direct_deny_ids) |> Enum.sort()
    grouped_denied_permissions = group_by_domain(denied_keys)

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

    socket
    |> assign(:can_edit?, can_edit?)
    |> assign(:assigned_roles, assigned_roles)
    |> assign(:assigned_role_ids, assigned_role_ids)
    |> assign(:has_grant_all?, has_grant_all?)
    |> assign(:grant_all_subject, grant_all_subject(assigned_roles))
    |> assign(:available_roles, available_roles)
    |> assign(
      :filtered_available_roles,
      filter_roles(available_roles, socket.assigns.role_search)
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
      filter_capabilities(grouped_available_capabilities, socket.assigns.capability_search)
    )
    |> assign(:capabilities_control, capabilities_control)
  end

  defp archived_refused(socket) do
    page_flash(
      socket,
      :error,
      "This user's company is archived, so the account can't be changed."
    )
  end

  # --- Event Handlers: Roles ---

  @impl true
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

        case Authz.unassign_role(scope, assignment.role_id, assignment.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> page_flash(:success, "The #{assignment.role_name} role was removed.")
             |> load_access()}

          {:error, _} ->
            {:noreply,
             page_flash(
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
             |> page_flash(:success, "#{cap_key} is denied for #{user.name}.")
             |> load_access()}

          {:error, _} ->
            {:noreply,
             page_flash(
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

        case Authz.remove_principal_capability(scope, grant_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> page_flash(:success, capability_removed_message(kind, cap_key))
             |> load_access()}

          {:error, _} ->
            {:noreply,
             page_flash(
               socket,
               :error,
               "The rule for #{cap_key} was not removed. Reload the page and try again."
             )}
        end
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

    {acting_grant_all?, acting_allowed_caps} = acting_permissions(current_scope)
    acting_allowed_set = MapSet.new(acting_allowed_caps)

    unauthorized_roles =
      parsed_role_ids
      |> grantable_role_ids(scope, acting_grant_all?, acting_allowed_set)
      |> then(fn grantable -> Enum.reject(parsed_role_ids, &(&1 in grantable)) end)

    cond do
      unauthorized_roles != [] ->
        {:noreply, page_flash(socket, :error, "You cannot grant roles you do not hold.")}

      parsed_role_ids != [] ->
        for role_id <- parsed_role_ids do
          Authz.assign_role(scope, user.company_id, :user, user.id, role_id)
        end

        count = length(parsed_role_ids)
        msg = if count == 1, do: "Assigned 1 role.", else: "Assigned #{count} roles."

        {:noreply,
         socket
         |> page_flash(:success, msg)
         |> assign(:selected_role_ids, [])
         |> assign(:show_assign_roles, false)
         |> load_access()}

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

    {acting_grant_all?, acting_allowed_caps} = acting_permissions(current_scope)
    acting_allowed_set = MapSet.new(acting_allowed_caps)

    unauthorized_caps =
      if acting_grant_all? do
        []
      else
        Enum.reject(cap_keys, &MapSet.member?(acting_allowed_set, &1))
      end

    cond do
      unauthorized_caps != [] ->
        {:noreply, page_flash(socket, :error, "You cannot grant capabilities you do not hold.")}

      cap_keys != [] ->
        for cap_key <- cap_keys do
          Authz.put_principal_capability(scope, user.company_id, :user, user.id, cap_key, true)
        end

        count = length(cap_keys)
        msg = if count == 1, do: "Granted 1 capability.", else: "Granted #{count} capabilities."

        {:noreply,
         socket
         |> page_flash(:success, msg)
         |> assign(:selected_capability_keys, [])
         |> load_access()}

      true ->
        {:noreply, socket}
    end
  end

  # --- Confirmation helpers ---

  defp hold_authz(socket, rule) do
    {:noreply, socket |> page_clear_flash() |> assign(:pending_authz, rule)}
  end

  defp capabilities_forbidden(socket) do
    {:noreply, page_flash(socket, :error, "You do not have permission to manage capabilities.")}
  end

  defp roles_forbidden(socket),
    do: page_flash(socket, :error, "You do not have permission to manage roles.")

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

  defp acting_permissions(%{grant_all: grant_all, capabilities: caps})
       when is_boolean(grant_all) and is_list(caps) do
    {grant_all, caps}
  end

  defp acting_permissions(%{actor: %Authz.Actor{} = actor}) do
    %{grant_all: grant_all, allowed: allowed} = Authz.effective_capabilities(actor)
    {grant_all, allowed}
  end

  defp acting_permissions(_current_scope), do: {false, []}

  defp grantable_roles(roles, scope, acting_grant_all?, %MapSet{} = acting_allowed_set) do
    grantable =
      roles
      |> Enum.map(& &1.id)
      |> grantable_role_ids(scope, acting_grant_all?, acting_allowed_set)
      |> MapSet.new()

    Enum.filter(roles, &MapSet.member?(grantable, &1.id))
  end

  defp grantable_role_ids(role_ids, scope, acting_grant_all?, %MapSet{} = acting_allowed_set) do
    grants = Authz.role_grants(scope, role_ids)

    Enum.filter(role_ids, fn role_id ->
      case Map.fetch(grants, role_id) do
        {:ok, grant} ->
          role_grantable?(grant, grant.capabilities, acting_grant_all?, acting_allowed_set)

        :error ->
          false
      end
    end)
  end

  defp role_grantable?(%{grant_all: true}, _capabilities, acting_grant_all?, %MapSet{}),
    do: acting_grant_all?

  defp role_grantable?(%{grant_all: false}, capabilities, true, %MapSet{})
       when is_list(capabilities),
       do: true

  defp role_grantable?(%{grant_all: false}, capabilities, false, %MapSet{} = acting_allowed_set)
       when is_list(capabilities) do
    Enum.all?(capabilities, &MapSet.member?(acting_allowed_set, &1))
  end

  defp role_grantable?(_grant, _capabilities, _acting_grant_all?, %MapSet{}), do: false

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

  defp grant_all_subject(assigned_roles) do
    case for row <- assigned_roles, row.role_grant_all, do: row.role_name do
      [] -> "An assigned role"
      names -> Enum.join(names, " and ")
    end
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

  # The `company_archived?` assign hides the controls. Each write asks Core
  # Company again, so a company archived after the page opened is still
  # refused, and the refusal is this panel's own words.
  defp archived_company?(socket) do
    scope = socket.assigns.current_scope.scope
    match?({:error, :not_found}, Company.get_company(scope, socket.assigns.user.company_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="user-access-panel">
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
                          phx-click={
                            JS.push("lv:clear-flash")
                            |> JS.push("request_remove_role", target: @myself)
                          }
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
                    phx-click="toggle_assign_roles" phx-target={@myself}
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
                  <form phx-change="search_roles" phx-submit="search_roles" id="role-search-form" phx-target={@myself}>
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
                    phx-target={@myself}
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
                        phx-click="toggle_assign_roles" phx-target={@myself}
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
                      reason={"#{@grant_all_subject} already grants every capability, so this user holds everything a role could add."}
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
                phx-click="toggle_effective_permissions" phx-target={@myself}
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
                                  phx-click={
                                    JS.push("lv:clear-flash")
                                    |> JS.push("request_remove_capability", target: @myself)
                                  }
                                  phx-value-grant-id={@direct_grant_ids[cap]}
                                />
                              <% else %>
                                <.icon_button
                                  icon="close"
                                  label={"Deny #{cap}"}
                                  context={:inline}
                                  kind={:danger}
                                  id={"deny-cap-#{String.replace(cap, ".", "-")}"}
                                  phx-click={
                                    JS.push("lv:clear-flash")
                                    |> JS.push("request_deny_capability", target: @myself)
                                  }
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
                            phx-click={
                              JS.push("lv:clear-flash")
                              |> JS.push("request_remove_capability", target: @myself)
                            }
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
                    phx-target={@myself}
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
                    phx-target={@myself}
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

      <.confirm_dialog
        :if={@pending_authz}
        id="user-authz-confirm"
        consequence={authz_consequence(@pending_authz, @user)}
        detail={authz_detail(@pending_authz, @user)}
        confirm={authz_verb(@pending_authz)}
        working={authz_working(@pending_authz)}
        on_confirm={JS.push(authz_event(@pending_authz), target: @myself)}
        on_cancel={JS.push("cancel_authz", target: @myself)}
      />
    </div>
    """
  end
end
