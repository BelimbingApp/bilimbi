defmodule Bilimbi.Base.Perf.DashboardWidget do
  @moduledoc "Dashboard contract for bounded performance health."

  @behaviour Bilimbi.Base.Dashboard.Widget

  @impl true
  def widget_title, do: "Performance health"

  @impl true
  def widget_size, do: :small

  @impl true
  def widget_refresh_interval, do: 60_000

  @impl true
  def widget_assigns, do: [:perf_diagnostics]
end
