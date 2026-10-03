defmodule Bilimbi.Base.Audit.Web.DashboardActivityPanel do
  @moduledoc """
  Dashboard widget: the five most recent audit mutations in this tenant.

  Contributed as the `"dashboard.activity"` embed; the dashboard renders it by
  that key and never names this module (ADR 0009). The feed is read again each
  time the dashboard counts a refresh, only after the socket is connected, and
  only while `admin.audit.log.list` is on the in-memory capability list.
  Otherwise the card shows an em dash and does not query.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Audit

  @capability "admin.audit.log.list"

  @impl true
  def update(assigns, socket) do
    stale? = socket.assigns[:refresh] != assigns.refresh
    socket = assign(socket, assigns)

    {:ok,
     cond do
       not socket.assigns.connected -> assign(socket, :entries, :not_loaded)
       not allowed?(socket.assigns.current_scope, @capability) ->
         assign(socket, :entries, :not_loaded)

       stale? -> load(socket)
       true -> socket
     end}
  end

  defp load(socket) do
    {:ok, entries} = Audit.list_recent_mutations(socket.assigns.current_scope.scope, 5)
    assign(socket, :entries, entries)
  end

  # Specialist: a time-ordered feed of audit entries has no label/value pairs, so not `stat_strip`.
  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.card
        id="stat-recent-audit"
        role="region"
        aria-labelledby="stat-recent-audit-heading"
        inner_class="p-5 sm:p-6"
      >
        <.section_heading id="stat-recent-audit-heading" title="Recent Activity">
          <:actions>
            <.icon_button
              :if={!@editing and allowed?(@current_scope, "admin.audit.log.list")}
              id="stat-recent-audit-open"
              icon="forward"
              label="Open audit log"
              context={:inline}
              navigate={~p"/audit/mutations"}
            />
          </:actions>
        </.section_heading>
        <div
          :if={@entries == :not_loaded}
          id="stat-recent-audit-pending"
          class="text-sm text-ink-subtle"
        >
          —
        </div>
        <.empty_state
          :if={is_list(@entries) and Enum.empty?(@entries)}
          id="stat-recent-audit-empty"
          title="No recent activity."
        />
        <div :if={is_list(@entries) and Enum.any?(@entries)} class="divide-y divide-line">
          <div
            :for={entry <- @entries}
            class="flex items-start gap-3 py-2.5 text-sm"
          >
            <.icon name="hero-document-text" class="size-4 shrink-0 text-ink-faint" />
            <div class="min-w-0 flex-1">
              <span class="font-medium text-ink">{entry.event}</span>
              <span class="ml-2 text-ink-subtle">{entry.auditable_type}</span>
            </div>
            <.datetime
              id={"audit-entry-#{entry.id}"}
              value={entry.occurred_at}
              class="text-xs tabular-nums text-ink-faint"
            />
          </div>
        </div>
      </.card>
    </div>
    """
  end
end
