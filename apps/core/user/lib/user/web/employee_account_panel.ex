defmodule Bilimbi.Core.User.Web.EmployeeAccountPanel do
  @moduledoc """
  Employee-page linked-account row, contributed as a discovered embed.

  Core User owns the `users.employee_id` link and every write behind this
  panel; the employee page renders it by the `"employee.accounts"` manifest
  key and never names this module (#581, mechanism from #570/#575).

  The agent invariant lives on this side of the seam now. Linking is refused
  by `Core.User.update_user` policy when the target employee is an agent, and
  when this panel observes an employee that became an agent while an account
  was still linked it reconciles by unlinking — Core User applying its own
  policy at its observation point, replacing the employee page's former
  probe-driven unlink. A failed reconciliation renders as a visible panel
  notice with the link still shown; nothing pretends to have succeeded (#409).

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
     |> reload()
     |> reconcile_agent_link()}
  end

  @impl true
  def handle_event("save_user", params, socket) do
    if can_manage_accounts?(socket.assigns.current_scope) do
      scope = socket.assigns.current_scope.scope
      current_linked = socket.assigns.linked_user

      target_user_id =
        case Integer.parse(to_string(params["user_id"] || "")) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      # Unlink the current user first. A failure here has to stop the link:
      # carrying on would leave two users pointing at this employee.
      unlink =
        if current_linked && current_linked.id != target_user_id do
          unlink_user(scope, socket.assigns.company_id, current_linked.id)
        else
          {:ok, nil}
        end

      result =
        with {:ok, _} <- unlink do
          if target_user_id do
            User.update_user(scope, socket.assigns.company_id, target_user_id, %{
              employee_id: socket.assigns.employee_id
            })
          else
            {:ok, nil}
          end
        end

      case result do
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
    {:ok, users} = User.list_company_users(scope, socket.assigns.company_id)

    linked_user = Enum.find(users, &(&1.employee_id == socket.assigns.employee_id))

    available_users =
      Enum.filter(
        users,
        &(is_nil(&1.employee_id) or &1.employee_id == socket.assigns.employee_id)
      )

    socket
    |> assign(:linked_user, linked_user)
    |> assign(:available_users, available_users)
  end

  # An agent holds no user account. The employee page no longer reaches into
  # Core User at type-change time; this panel observes the type on every
  # update and unlinks under Core User's own authority.
  defp reconcile_agent_link(
         %{assigns: %{employee_type: "agent", linked_user: %{} = linked}} = socket
       ) do
    scope = socket.assigns.current_scope.scope

    case unlink_user(scope, socket.assigns.company_id, linked.id) do
      {:ok, _} ->
        socket
        |> notice(:info, "Unlinked #{linked.name}: an agent holds no user account.")
        |> reload()

      {:error, _} ->
        notice(
          socket,
          :error,
          "#{linked.name} is still linked but an agent holds no user account. The unlink failed; retry or unlink from the user page."
        )
    end
  end

  defp reconcile_agent_link(socket), do: socket

  defp unlink_user(scope, company_id, user_id) do
    User.update_user(scope, company_id, user_id, %{employee_id: nil})
  end

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
