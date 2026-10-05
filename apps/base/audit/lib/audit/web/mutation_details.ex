defmodule Bilimbi.Base.Audit.Web.MutationDetails do
  @moduledoc """
  The details cell of one mutations-table row.

  The table streams up to 300 rows. Rendering every old and new value inline
  made each row about 15 KB and the page several megabytes. This paints
  `MutationDiff.summary/1` and builds the field diff only while the row is
  open. The values stay on the server either way; the closed row does not
  send them.

  It is a disclosure button, not a data-changing `<.button>`. `aria-expanded`
  follows the open state. Opening moves focus into the diff. A second
  activation closes it. Click-away is not a close: a reader selecting text
  in the diff must not lose it.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Audit.Web.MutationDiff
  alias Phoenix.LiveView.JS

  import MutationDiff, only: [diff_value: 1]

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:open, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open, not socket.assigns.open)}
  end

  @impl true
  def render(assigns) do
    fields = MutationDiff.changed_fields(assigns.mutation)

    assigns =
      assigns
      |> assign(:empty?, fields == [])
      |> assign(:summary, MutationDiff.summary_from_fields(fields))

    ~H"""
    <div id={@id}>
      <span :if={@empty?} class="text-xs italic text-ink-muted">
        No field changes recorded.
      </span>
      <button
        :if={not @empty?}
        type="button"
        id={"#{@id}-toggle"}
        phx-click="toggle"
        phx-target={@myself}
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-diff"}
        class="max-w-full truncate text-left font-mono text-xs text-link hover:underline"
      >
        {@summary}
      </button>
      <div
        :if={@open}
        id={"#{@id}-diff"}
        tabindex="-1"
        phx-mounted={JS.focus()}
        class="mt-1 space-y-1 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
      >
        <div
          :for={diff <- MutationDiff.rows(@mutation)}
          class="flex items-baseline gap-2 font-mono text-xs"
        >
          <span class="min-w-[100px] font-semibold text-ink-muted">{diff.field}:</span>
          <code :if={diff.sensitive} class="text-ink-muted italic">
            <.diff_value id={"mutation-#{@mutation.id}-#{diff.field}-old"} value={diff.old} /> →
            <.diff_value id={"mutation-#{@mutation.id}-#{diff.field}-new"} value={diff.new} />
          </code>
          <div :if={!diff.sensitive} class="flex items-baseline gap-1.5 flex-wrap">
            <code class="text-status-danger">
              <.diff_value id={"mutation-#{@mutation.id}-#{diff.field}-old"} value={diff.old} />
            </code>
            <span class="text-ink-muted">→</span>
            <code class="text-status-success">
              <.diff_value id={"mutation-#{@mutation.id}-#{diff.field}-new"} value={diff.new} />
            </code>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
