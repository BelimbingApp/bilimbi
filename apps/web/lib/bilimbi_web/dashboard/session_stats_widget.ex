defmodule BilimbiWeb.Dashboard.SessionStatsWidget do
  @moduledoc "Widget: durable session count, refreshed while the dashboard is open."
  @behaviour Bilimbi.Base.Dashboard.Widget

  @impl true
  def widget_title, do: "Sessions"

  @impl true
  def widget_size, do: :small

  @impl true
  def widget_refresh_interval, do: 60_000

  @impl true
  def widget_assigns, do: [:session_count]
end
