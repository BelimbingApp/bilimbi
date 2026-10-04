defmodule Bilimbi.Core.User.Web.DashboardStatsPanel do
  @moduledoc """
  Dashboard widget: tenant-wide account counts.

  Contributed as the `"dashboard.users"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). The counts are read once
  when the panel is placed, as they were before the widget moved here.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Core.User

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns[:summary], do: socket, else: load(socket))}
  end

  defp load(socket) do
    {:ok, summary} = User.dashboard_summary(socket.assigns.current_scope.scope)
    assign(socket, :summary, summary)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.stat_strip
        id="stat-users"
        title="Users"
        navigate={if !@editing and allowed?(@current_scope, "admin.user.list"), do: ~p"/users"}
      >
        <:item label="Total" value={@summary.total} />
        <:item label="Verified" value={@summary.verified} />
        <:item label="Pending" value={@summary.unverified} />
      </.stat_strip>
    </div>
    """
  end
end
