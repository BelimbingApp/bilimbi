defmodule Bilimbi.Core.Company.Web.DashboardStatsPanel do
  @moduledoc """
  Dashboard widget: live company counts and the viewer's current company code.

  Contributed as the `"dashboard.companies"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). The counts are read once
  when the panel is placed, as they were before the widget moved here.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Core.Company

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns[:summary], do: socket, else: load(socket))}
  end

  defp load(socket) do
    current_scope = socket.assigns.current_scope

    {:ok, summary} =
      Company.dashboard_summary(current_scope.scope, current_scope.user["company_id"])

    assign(socket, :summary, summary)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.stat_strip
        id="stat-companies"
        title="Companies"
        navigate={if !@editing and allowed?(@current_scope, "admin.company.list"), do: ~p"/companies"}
      >
        <:item label="Total" value={@summary.total} />
        <:item label="Active" value={@summary.active} />
        <:item
          label="Current"
          kind={:text}
          value={(@summary.company && @summary.company.code) || "—"}
        />
      </.stat_strip>
    </div>
    """
  end
end
