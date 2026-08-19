defmodule BilimbiWeb.Dashboard.CompanyStatsWidget do
  @moduledoc "Widget: company count with link to companies list."
  @behaviour Bilimbi.Base.Dashboard.Widget

  @impl true
  def widget_title, do: "Companies"

  @impl true
  def widget_size, do: :small

  @impl true
  def widget_refresh_interval, do: 0

  @impl true
  def widget_assigns, do: [:company_count]
end
