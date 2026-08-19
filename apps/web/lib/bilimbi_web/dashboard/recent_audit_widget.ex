defmodule BilimbiWeb.Dashboard.RecentAuditWidget do
  @moduledoc "Widget: recent audit mutation entries."
  @behaviour Bilimbi.Base.Dashboard.Widget

  @impl true
  def widget_title, do: "Recent Activity"

  @impl true
  def widget_size, do: :medium

  @impl true
  def widget_refresh_interval, do: 120_000

  @impl true
  def widget_assigns, do: [:audit_entries]
end
