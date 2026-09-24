defmodule Bilimbi.Base.Audit.Web.RecordHistory do
  @moduledoc """
  Header affordance for a single auditable record's recent mutation trail.

  The trigger is a demoted labelled action: the registry's `history` glyph
  (the clock Belimbing uses for the same action) beside the word "History",
  in the one quiet treatment `Bilimbi.Base.UI.Components.demoted_action_class/0`
  gives every demoted header action. Belimbing's `admin/*/show` pages present
  it exactly so, as a labelled ghost control in the row with Impersonate and
  Back, so the word is visible rather than kept for assistive technology.

  It is a disclosure button, the same contract the shell's account and
  timezone disclosures and the notification bell keep. `aria-expanded`
  follows the server's open state. Opening moves focus into the panel.
  Escape closes it and returns focus to the trigger, and a click outside
  closes it. The panel exists only while open, so a closed history never
  claims Escape. The trigger is not a data-changing `<.button>`: it discloses.

  ## Staying current

  The trail is read from the database, so it is only as fresh as the last
  time this component ran. Two things keep it truthful:

    * The panel re-reads the trail every time it is opened, so what the
      reader sees on opening it is the record's history as of that moment,
      whoever wrote it. The open state is the server's (`aria-expanded` and
      whether the panel is rendered), because a browser-only open flag would
      be dropped by the next DOM patch, and the trigger's click flips both
      in step.
    * The page passes the record itself as `record`, beside the
      `auditable_id` the read needs. A LiveView re-renders a component only
      when an assign it was given changes, and it tracks `@user.id` at the
      field level, so the id alone never re-renders this panel after an
      in-page edit — the trail stood still while the page's own Updated
      fact moved. The whole record changes with every write, so passing it
      is what re-runs `update/2`, and an open panel follows the edit.

  Values inside a diff render through `Bilimbi.Base.Audit.Web.MutationDiff`,
  so a stored timestamp shows in the page's chosen clock, the same as the
  entry's own time beside the badge.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Web.MutationDiff

  import MutationDiff, only: [diff_value: 1]

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:title, fn -> "Record History" end)
      |> assign_new(:open, fn -> false end)

    {:ok, load_entries(socket)}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    if socket.assigns.open do
      {:noreply, assign(socket, :open, false)}
    else
      {:noreply, socket |> assign(:open, true) |> load_entries()}
    end
  end

  # Click-away and Escape close. They do not toggle: a click outside a
  # closed history still reaches this handler, and opening it would turn
  # every page click into a disclosure.
  @impl true
  def handle_event("close", _params, %{assigns: %{open: true}} = socket) do
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, socket}
  end

  defp load_entries(socket) do
    {:ok, entries} =
      Audit.list_subject_mutations(
        socket.assigns.current_scope.scope,
        socket.assigns.auditable_types,
        socket.assigns.auditable_id
      )

    assign(socket, :entries, entries)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative inline-block text-left"
      phx-click-away={if(@open, do: JS.push("close", target: @myself))}
    >
      <button
        type="button"
        id={"#{@id}-toggle"}
        title="History"
        phx-click="toggle"
        phx-target={@myself}
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-panel"}
        class={[Bilimbi.Base.UI.Components.demoted_action_class(), "cursor-pointer"]}
      >
        <.icon name="history" class="size-4" /> History
      </button>

      <%!-- The panel follows the shell's disclosures and the notification
           bell: it mounts only while open, so phx-mounted moves focus in
           and the Escape listener exists only then. The panel itself is
           focusable because a trail is text, not a list of controls. --%>
      <div
        :if={@open}
        id={"#{@id}-panel"}
        tabindex="-1"
        aria-labelledby={"#{@id}-heading"}
        phx-mounted={JS.focus()}
        phx-window-keydown={JS.push("close", target: @myself) |> JS.focus(to: "##{@id}-toggle")}
        phx-key="escape"
        class="absolute right-0 z-40 mt-2 w-[min(34rem,calc(100vw-2rem))] rounded-xl border border-line bg-surface p-3 text-left shadow-xl shadow-ink/[0.08] focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
      >
          <div class="flex items-start justify-between gap-3 border-b border-line pb-2">
            <div>
              <h2 id={"#{@id}-heading"} class="text-sm font-semibold text-ink">{@title}</h2>
              <p class="text-xs text-ink-muted">{history_count(@entries)}</p>
            </div>
          </div>

          <ol :if={@entries != []} class="mt-2 max-h-96 space-y-2 overflow-y-auto">
            <li
              :for={entry <- @entries}
              id={"#{@id}-entry-#{entry.id}"}
              class="rounded-lg border border-line bg-surface px-3 py-2"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <% {badge_kind, badge_label} = event_badge(entry.event) %>
                <.badge kind={badge_kind}>{badge_label}</.badge>
                <.datetime
                  id={"#{@id}-entry-#{entry.id}-occurred"}
                  value={entry.occurred_at}
                  class="text-xs text-ink-muted"
                />
              </div>

              <div class="mt-1 text-xs text-ink-muted">
                {actor_label(entry)}
              </div>

              <% field_diffs = MutationDiff.rows(entry) %>
              <div :if={field_diffs != []} class="mt-2 space-y-1">
                <div :for={diff <- field_diffs} class="grid grid-cols-[7rem_minmax(0,1fr)] gap-2 font-mono text-xs">
                  <span class="truncate font-semibold text-ink-muted">{diff.field}</span>
                  <span class="min-w-0 truncate text-ink">
                    <%= if diff.sensitive do %>
                      redacted
                    <% else %>
                      <.diff_value
                        id={"#{@id}-entry-#{entry.id}-#{diff.field}-old"}
                        value={diff.old}
                        class="text-danger-ink"
                      />
                      <span class="px-1 text-ink-muted">-></span>
                      <.diff_value
                        id={"#{@id}-entry-#{entry.id}-#{diff.field}-new"}
                        value={diff.new}
                        class="text-success-ink"
                      />
                    <% end %>
                  </span>
                </div>
              </div>
              <p :if={field_diffs == []} class="mt-2 text-xs italic text-ink-muted">
                No field changes recorded.
              </p>
            </li>
          </ol>

          <p :if={@entries == []} id={"#{@id}-empty"} class="mt-3 rounded-lg bg-surface-sunken px-3 py-6 text-center text-sm text-ink-muted">
            No record history found.
          </p>
        </div>
    </div>
    """
  end

  defp history_count([]), do: "No recent mutations"
  defp history_count([_]), do: "1 recent mutation"
  defp history_count(entries), do: "#{length(entries)} recent mutations"

  defp actor_label(%{impersonator_id: impersonator_id} = entry)
       when is_integer(impersonator_id) and impersonator_id > 0 do
    "#{actor_label(Map.put(entry, :impersonator_id, nil))} · impersonated by User ##{impersonator_id}"
  end

  defp actor_label(%{actor_type: "user", actor_id: id}) when is_integer(id) and id > 0,
    do: "User ##{id}"

  defp actor_label(%{actor_type: "agent", actor_id: id}) when is_integer(id) and id > 0,
    do: "Employee ##{id}"

  defp actor_label(%{actor_type: "guest"}), do: "Guest"
  defp actor_label(%{actor_type: "console"}), do: "Console"
  defp actor_label(%{actor_type: "scheduler"}), do: "Scheduler"
  defp actor_label(%{actor_type: "queue"}), do: "Queue"

  defp actor_label(%{actor_type: type, actor_id: id}) when is_integer(id) and id > 0,
    do: "#{String.capitalize(type)} ##{id}"

  defp actor_label(%{actor_type: type}) when is_binary(type), do: String.capitalize(type)
  defp actor_label(_entry), do: "-"

  defp event_badge("created"), do: {:success, "Created"}
  defp event_badge("deleted"), do: {:danger, "Deleted"}
  defp event_badge("updated"), do: {:neutral, "Updated"}
  defp event_badge(other), do: {:neutral, String.capitalize(to_string(other))}
end
