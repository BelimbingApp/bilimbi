defmodule Bilimbi.Core.User.Web.EmployeeAccountPanel do
  @moduledoc """
  Employee-page linked-account row, contributed as a discovered embed.

  Core User owns the `users.employee_id` link and every write behind this
  panel; the employee page renders it by the `"employee.accounts"` manifest
  key and never names this module (#581, mechanism from #570/#575).

  The panel also declares the operations the employee pages use for account
  choices, replacement, and type transitions. Those operations run through the
  manifest resolver rather than a reverse module reference, and delegate to
  Core User's transaction-safe coordinators so the User-owned account link never
  has to be read or written from Core Employee.

  Every write re-evaluates the actor's current grants through `Authz.can/2`
  (the #482/#541 pattern); mount-time capability state is presentation, not
  an authorization decision. Outcomes render as a panel-local notice because
  a LiveComponent cannot reach the page's flash without a parent contract.
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
          {:noreply, socket |> notice(:info, "User link updated.") |> reload()}

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
    <div id={@id} class="contents">
      <div :if={@employee_type != "agent" or @notice} id={"#{@id}-row"}>
        <dt class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle">
          User
        </dt>

        <dd class="mt-0.5 text-sm text-ink">
          <div
            :if={@notice}
            id={"#{@id}-notice"}
            class={[
              "mb-1.5 rounded-lg border px-2.5 py-1.5 text-xs",
              elem(@notice, 0) == :info && "border-line bg-brand-surface text-ink",
              elem(@notice, 0) == :error && "border-danger/40 bg-surface text-danger"
            ]}
          >
            {elem(@notice, 1)}
          </div>

          <%= if @employee_type != "agent" do %>
            <%= if @can_manage? do %>
              <form
                phx-change="save_user"
                phx-target={@myself}
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
          <% end %>
        </dd>
      </div>
    </div>
    """
  end
end
