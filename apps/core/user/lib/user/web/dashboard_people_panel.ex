defmodule Bilimbi.Core.User.Web.DashboardPeoplePanel do
  @moduledoc """
  Dashboard section: a bounded preview of the accounts in this workspace.

  Contributed as the `"dashboard.people"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). The preview is the first
  five accounts `User.dashboard_summary/1` returns.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Core.User

  @builtins [
    %{id: "name", label: "Name", type: :string},
    %{id: "email", label: "Email", type: :string},
    %{id: "email_verified", label: "Email verified", type: :string}
  ]

  @write_guard_opt_out ~w(people_grid)

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    socket = if socket.assigns[:users], do: socket, else: load(socket)
    columns = socket.assigns[:columns] || ListColumns.mount("dashboard-users", @builtins)
    {:ok, assign(socket, :columns, ListColumns.load(columns, socket.assigns.users, & &1.id))}
  end

  @impl true
  def handle_event("people_grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      _other -> {:noreply, socket}
    end
  end

  defp load(socket) do
    {:ok, summary} = User.dashboard_summary(socket.assigns.current_scope.scope)
    assign(socket, :users, summary.users)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.card
        id="dashboard-recent-users"
        role="region"
        aria-labelledby="dashboard-recent-users-heading"
        inner_class="p-0"
      >
        <div class="px-5 pt-5 sm:px-6 sm:pt-6">
          <.section_heading id="dashboard-recent-users-heading" title="People in this workspace">
            <:actions>
              <.action_link
                :if={!@editing and allowed?(@current_scope, "admin.user.list")}
                id="dashboard-users-open"
                icon="forward"
                navigate={~p"/users"}
                title="All users"
              >
                All users
              </.action_link>
            </:actions>
          </.section_heading>
        </div>
        <.flex_table
          id="dashboard-users"
          framed={false}
          columns={@columns.column_views}
          rows={@columns.rows}
          mode={@columns.mode}
          zoom={@columns.zoom}
          suggestions={@columns.suggestions}
          add_query={@columns.add_query}
          event="people_grid"
          target={@myself}
          row_id={&"dashboard-user-#{&1}"}
          caption="People in this workspace"
        >
          <:col :let={%{record: user}} id="name">
            <span class="font-medium">{user.name}</span>
          </:col>
          <:col :let={%{record: user}} id="email">{user.email}</:col>
          <:col :let={%{record: user}} id="email_verified">
            <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
              {if user.email_verified_at, do: "verified", else: "unverified"}
            </.badge>
          </:col>
          <:empty :if={@users == []}>
            No users are affiliated with a company in this tenant yet.
          </:empty>
        </.flex_table>
      </.card>
    </div>
    """
  end
end
