defmodule Bilimbi.Base.Session.Web.DashboardStatsPanel do
  @moduledoc """
  Dashboard widget: how many durable sessions exist right now.

  Contributed as the `"dashboard.sessions"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). The count is platform-wide,
  as `Session.count_sessions/0` documents, and is read again each time the
  dashboard counts a refresh, and only after the socket is connected. Until
  then the strip shows an em dash and does not query.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Session

  @impl true
  def update(assigns, socket) do
    stale? = socket.assigns[:refresh] != assigns.refresh
    socket = assign(socket, assigns)

    {:ok,
     cond do
       not socket.assigns.connected -> assign(socket, :count, :not_loaded)
       stale? -> assign(socket, :count, Session.count_sessions())
       true -> socket
     end}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.stat_strip
        id="stat-sessions"
        title="Sessions"
        navigate={
          if !@editing and allowed?(@current_scope, "admin.system.session.list"),
            do: ~p"/system/sessions"
        }
      >
        <:item label="Open" value={shown(@count)} />
        <:item label="Store" kind={:text} value="Durable" />
        <:item label="Scope" kind={:text} value="Platform" />
      </.stat_strip>
    </div>
    """
  end

  defp shown(:not_loaded), do: "—"
  defp shown(value), do: value
end
