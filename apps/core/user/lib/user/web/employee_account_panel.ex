defmodule Bilimbi.Core.User.Web.EmployeeAccountPanel do
  @moduledoc """
  Employee-page linked-account fact, contributed as a discovered embed.

  Core User owns the `users.employee_id` link and every write behind this
  panel; the employee page renders it by the `"employee.accounts"` manifest
  key and never names this module (#581, mechanism from #570/#575). The page
  owns the row: it names the "User" fact in its shared `<.list>` and decides
  whether an employee has one (an agent does not), and this panel renders
  only the value cell — the outcome notice, then the account choice for an
  operator who may manage employees or the linked account for anyone else.

  The panel also declares the operations the employee pages use for account
  choices, replacement, and type transitions. Those operations run through the
  manifest resolver rather than a reverse module reference, and delegate to
  Core User's transaction-safe coordinators so the User-owned account link never
  has to be read or written from Core Employee.

  Every write re-evaluates the actor's current grants through `Authz.can/2`
  (the #482/#541 pattern); mount-time capability state is presentation, not
  an authorization decision. Outcomes render through the shared
  `<.panel_notice>` because a LiveComponent cannot reach the page's flash
  without a parent contract; a completed write says `:success` there, as it
  would in the page's flash, and a refusal or failure `:error`.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.User

  @manage_capability "admin.employee.update"

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :notice, nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:can_manage?, can_manage_accounts?(assigns.current_scope))
     |> reload()}
  end

  @impl true
  def handle_event("save_user", params, socket) do
    if can_manage_accounts?(socket.assigns.current_scope) do
      scope = socket.assigns.current_scope.scope

      target_user_id =
        case Integer.parse(to_string(params["user_id"] || "")) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      case User.replace_employee_account(
             scope,
             socket.assigns.company_id,
             socket.assigns.employee_id,
             target_user_id
           ) do
        {:ok, _} ->
          {:noreply, socket |> notice(:success, "User link updated.") |> reload()}

        {:error, _} ->
          {:noreply,
           socket
           |> notice(:error, "Failed to update linked user account.")
           |> reload()}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("clear_notice", _params, socket) do
    {:noreply, assign(socket, :notice, nil)}
  end

  # --- Data & helpers ---

  defp reload(socket) do
    scope = socket.assigns.current_scope.scope

    # Deliberately strict: the page resolved this employee's company before
    # rendering the panel, so a non-ok here is infrastructure failure —
    # raising reaches the recovery boundary instead of rendering a broken
    # section as an empty one (#409).
    {:ok, account_state} =
      account_state(scope, socket.assigns.company_id, socket.assigns.employee_id)

    socket
    |> assign(:linked_user, account_state.linked_user)
    |> assign(:available_users, account_state.available_users)
  end

  @doc false
  def dispatch(:employee_account_options, scope, company_id, current_employee_id) do
    account_state(scope, company_id, current_employee_id)
  end

  def dispatch(:replace_employee_account, scope, company_id, employee_id, user_id) do
    User.replace_employee_account(scope, company_id, employee_id, user_id)
  end

  def dispatch(:change_employee_type, scope, company_id, employee_id, type) do
    User.change_employee_type(scope, company_id, employee_id, type)
  end

  defp account_state(scope, company_id, current_employee_id) do
    with {:ok, users} <- User.list_company_users(scope, company_id) do
      linked_user =
        if is_integer(current_employee_id) do
          Enum.find(users, &(&1.employee_id == current_employee_id))
        end

      available_users = Enum.filter(users, &available_for_employee?(&1, current_employee_id))

      {:ok,
       %{
         linked_user: linked_user,
         linked_user_id: linked_user && linked_user.id,
         available_users: available_users
       }}
    end
  end

  defp available_for_employee?(user, nil), do: is_nil(user.employee_id)

  defp available_for_employee?(user, employee_id),
    do: is_nil(user.employee_id) or user.employee_id == employee_id

  defp can_manage_accounts?(current_scope) do
    Authz.can(current_scope.actor, @manage_capability).allowed
  end

  defp write_forbidden(socket) do
    socket
    |> assign(:can_manage?, false)
    |> notice(:error, "You do not have permission to edit employees.")
  end

  defp notice(socket, kind, message), do: assign(socket, :notice, {kind, message})

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.panel_notice
        :if={@notice}
        id={"#{@id}-notice"}
        kind={elem(@notice, 0)}
        on_dismiss={JS.push("clear_notice", target: @myself)}
        class="mb-1.5"
      >
        {elem(@notice, 1)}
      </.panel_notice>

      <%= if @can_manage? do %>
        <form
          phx-change="save_user"
          phx-target={@myself}
          id="employee-user-form"
          class="inline-flex flex-wrap items-center gap-2"
        >
          <select
            id="employee-user"
            name="user_id"
            aria-label="Linked user account"
            class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
          >
            <option value="" selected={is_nil(@linked_user)}>None</option>

            <%= for u <- @available_users do %>
              <option value={u.id} selected={@linked_user && @linked_user.id == u.id}>
                {u.name}
              </option>
            <% end %>
          </select>

          <.link
            :if={@linked_user}
            id="employee-user-link"
            navigate={~p"/users/#{@linked_user.id}"}
            class="text-xs font-medium text-action hover:underline"
          >
            {@linked_user.name}
          </.link>
        </form>
      <% else %>
        <.link
          :if={@linked_user}
          id="employee-user-link"
          navigate={~p"/users/#{@linked_user.id}"}
          class="text-action hover:underline"
        >
          {@linked_user.name}
        </.link>
        <span :if={is_nil(@linked_user)} class="text-ink-muted">None</span>
      <% end %>
    </div>
    """
  end
end
