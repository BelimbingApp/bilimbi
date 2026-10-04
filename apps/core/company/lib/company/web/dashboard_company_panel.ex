defmodule Bilimbi.Core.Company.Web.DashboardCompanyPanel do
  @moduledoc """
  Dashboard section: the viewer's current company.

  Contributed as the `"dashboard.company"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). A tenant with no live
  company says so here instead of leaving a gap the reader cannot explain.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Core.Company

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(Map.has_key?(socket.assigns, :company), do: socket, else: load(socket))}
  end

  defp load(socket) do
    current_scope = socket.assigns.current_scope

    {:ok, summary} =
      Company.dashboard_summary(current_scope.scope, current_scope.user["company_id"])

    assign(socket, :company, summary.company)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.card
        :if={@company}
        id="dashboard-current-company"
        data-company-id={@company.id}
        role="region"
        aria-labelledby="dashboard-current-company-heading"
        inner_class="p-5 sm:p-6"
      >
        <.section_heading id="dashboard-current-company-heading" title="Your company">
          <:actions>
            <.action_link
              :if={!@editing and allowed?(@current_scope, "admin.company.view")}
              id="dashboard-company-open"
              icon="forward"
              navigate={~p"/companies/#{@company.id}"}
              title="Open company"
            >
              Open company
            </.action_link>
          </:actions>
        </.section_heading>
        <.list id="dashboard-company-facts">
          <:item title="Name" id="dashboard-company-name">
            {Company.Summary.display_name(@company)}
          </:item>
          <:item title="Code">
            <code class="font-medium">{@company.code}</code>
          </:item>
          <:item title="Status">
            <.badge kind={if @company.status == "active", do: :success, else: :warning}>
              {@company.status}
            </.badge>
          </:item>
        </.list>
      </.card>
      <.empty_state
        :if={is_nil(@company)}
        id="dashboard-current-company-none"
        title="No company yet."
        reason="This workspace has no live company to show."
      />
    </div>
    """
  end
end
