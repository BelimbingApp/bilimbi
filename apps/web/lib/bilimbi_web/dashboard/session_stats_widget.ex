defmodule BilimbiWeb.Dashboard.SessionStatsWidget do
  @moduledoc "Widget: active session count with link to session list."
  @behaviour Bilimbi.Base.Dashboard.Widget

  @impl true
  def widget_title, do: "Active Sessions"

  @impl true
  def widget_size, do: :small

  @impl true
  def widget_refresh_interval, do: 300_000

  @impl true
  def widget_assigns, do: [:session_count]
end
