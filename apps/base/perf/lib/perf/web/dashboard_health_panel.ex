defmodule Bilimbi.Base.Perf.Web.DashboardHealthPanel do
  @moduledoc """
  Dashboard widget: bounded performance-history health.

  Contributed as the `"dashboard.performance"` embed; the dashboard renders it
  by that key and never names this module (ADR 0009). Health is read again
  each time the dashboard counts a refresh.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Perf

  @impl true
  def update(assigns, socket) do
    stale? = socket.assigns[:refresh] != assigns.refresh
    socket = assign(socket, assigns)
    {:ok, if(stale?, do: assign(socket, :diagnostics, Perf.diagnostics()), else: socket)}
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

  defp health(%{store: :unavailable}), do: "History unavailable"
  defp health(%{recorder: :unavailable}), do: "Recorder unavailable"
  defp health(%{recorder: :degraded, store: :available}), do: "Degraded"
  defp health(%{recorder: :available, store: :available}), do: "Available"
  defp health(_diagnostics), do: "Unknown"

  defp samples(%{samples: samples}) when is_integer(samples), do: samples
  defp samples(_diagnostics), do: "—"
end
