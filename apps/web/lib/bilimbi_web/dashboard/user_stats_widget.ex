defmodule BilimbiWeb.Dashboard.UserStatsWidget do
  @moduledoc "Widget: user count with link to users list."
  @behaviour Bilimbi.Base.Dashboard.Widget

  @impl true
  def widget_title, do: "Users"

  @impl true
  def widget_size, do: :small

  @impl true
  def widget_refresh_interval, do: 0

  @impl true
  def widget_assigns, do: [:user_count]
end
