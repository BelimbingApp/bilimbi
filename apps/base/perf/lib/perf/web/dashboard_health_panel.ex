defmodule Bilimbi.Base.Perf.Web.DashboardHealthPanel do
  @moduledoc """
  Dashboard widget: bounded performance-history health.

  Contributed as the `"dashboard.performance"` embed; the dashboard renders it
  by that key and never names this module (ADR 0009). Health is read again
  each time the dashboard counts a refresh, only after the socket is
  connected, and only while `admin.system.perf.view` is on the in-memory
  capability list. Otherwise the strip shows an em dash and does not query.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Perf

  @capability "admin.system.perf.view"

  @impl true
  def update(assigns, socket) do
    stale? = socket.assigns[:refresh] != assigns.refresh
    socket = assign(socket, assigns)

    {:ok,
     cond do
       not socket.assigns.connected ->
         assign(socket, :diagnostics, :not_loaded)

       not allowed?(socket.assigns.current_scope, @capability) ->
         assign(socket, :diagnostics, :not_loaded)

       stale? ->
         assign(socket, :diagnostics, Perf.diagnostics())

       true ->
         socket
     end}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.stat_strip
        id="stat-performance"
        title="Performance"
        navigate={if !@editing, do: ~p"/system/performance"}
      >
        <:item label="Health" kind={:text} value={health(@diagnostics)} />
        <:item label="Samples" value={samples(@diagnostics)} />
      </.stat_strip>
    </div>
    """
  end

  defp health(:not_loaded), do: "—"
  defp health(%{store: :unavailable}), do: "History unavailable"
  defp health(%{recorder: :unavailable}), do: "Recorder unavailable"
  defp health(%{recorder: :degraded, store: :available}), do: "Degraded"
  defp health(%{recorder: :available, store: :available}), do: "Available"
  defp health(_diagnostics), do: "Unknown"

  defp samples(:not_loaded), do: "—"
  defp samples(%{samples: samples}) when is_integer(samples), do: samples
  defp samples(_diagnostics), do: "—"
end
