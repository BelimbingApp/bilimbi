defmodule Bilimbi.Core.User.Web.DashboardPeoplePanel do
  @moduledoc """
  Dashboard section: a bounded preview of the accounts in this workspace.

  Contributed as the `"dashboard.people"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). The preview is the first
  five accounts `User.dashboard_summary/1` returns.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Core.User

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns[:users], do: socket, else: load(socket))}
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
        inner_class="p-5 sm:p-6"
      >
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
        <.table
          id="dashboard-users"
          rows={@users}
          row_id={&"dashboard-user-#{&1.id}"}
          caption="People in this workspace"
          framed={false}
        >
          <:col :let={user} label="Name">
            <span class="font-medium">{user.name}</span>
          </:col>
          <:col :let={user} label="Email">{user.email}</:col>
          <:col :let={user} label="Email verified">
            <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
              {if user.email_verified_at, do: "verified", else: "unverified"}
            </.badge>
          </:col>
          <:empty :if={@users == []}>
            No users are affiliated with a company in this tenant yet.
          </:empty>
        </.table>
      </.card>
    </div>
    """
  end
end
