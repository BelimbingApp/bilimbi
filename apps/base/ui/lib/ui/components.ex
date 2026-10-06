defmodule Bilimbi.Base.UI.Components do
  @moduledoc """
  Provides core UI components.

  The components are split by stable group. This module holds feedback,
  actions, page structure, inline editing and the tile chrome;
  `Bilimbi.Base.UI.Components.Icon` holds the icon,
  `Bilimbi.Base.UI.Components.Forms` the form controls,
  `Bilimbi.Base.UI.Components.Lists` the operational-list surface and
  `Bilimbi.Base.UI.Components.FlexTable` the flexible table. A caller
  takes all of them with `use Bilimbi.Base.UI.Components`; `modules/0` is the
  list anything that enumerates components reads. A group imports only the
  groups below it (Icon, then Forms, then Lists), and this module imports
  Icon alone, so the compiler refuses a cycle. FlexTable sits above them all:
  it imports this module and Lists, and nothing imports it.

  The components consist mostly of markup and are well-documented with doc
  strings and declarative assigns.

  The foundation for styling is Tailwind CSS. Bilimbi owns its component
  design directly rather than delegating product appearance to a component
  theme. Every component here styles itself with the semantic color roles
  declared in `assets/css/app.css` — `surface`, `ink`, `line`, `action`,
  `brand`, `success`, `info`, `warning`, and `danger`. A raw palette class such as
  `stone-200` or `emerald-600` does not belong in a component or a template.

  Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the utility framework used
      for layout, sizing, color, typography, and interaction states.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Bilimbi.Base.UI.Components.Icon

  alias Bilimbi.Base.UI.Components.FlexTable
  alias Bilimbi.Base.UI.Components.Forms
  alias Bilimbi.Base.UI.Components.Icon
  alias Bilimbi.Base.UI.Components.Lists
  alias Phoenix.LiveView.JS

  @doc """
  Imports every component group.

  A plain `import Bilimbi.Base.UI.Components` brings only the components this
  module still defines, so `<.icon>`, `<.input>` and `<.table>` would be
  undefined.
  """
  defmacro __using__(_opts) do
    quote do
      import Bilimbi.Base.UI.Components, except: [modules: 0]
      import Bilimbi.Base.UI.Components.Icon
      import Bilimbi.Base.UI.Components.Forms, except: [field_base_class: 1, field_base_class: 2]
      import Bilimbi.Base.UI.Components.Lists
      import Bilimbi.Base.UI.Components.FlexTable
    end
  end

  @doc """
  Every module that defines shared components, this one included.

  The Design Library guards read it, so a component moved to a new group is
  still measured.
  """
  @spec modules() :: [module()]
  def modules, do: [__MODULE__, Icon, Forms, Lists, FlexTable]

  @doc """
  Renders one flash message.

  The message is the flash entry for `kind`, or the inner block. Each kind
  has a colour role of its own: a completed write is `:success`, a statement
  that informs without confirming one is `:info` and reads on the blue `info`
  role, so the two never look alike. Announcement follows the same split as
  Belimbing's alert: success and info are a polite `status`, while warning
  and error interrupt as an assertive `alert`.

  Clicking the message clears it on the server and hides it. The component
  itself never dismisses on a timer; `Bilimbi.Base.UI.Layouts.flash_group/1`,
  the one production outlet, stacks the messages and decides which of them
  time out, so a message a person must act on stays until they dismiss it.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:success}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)

  attr(:kind, :atom,
    values: [:success, :info, :warning, :error],
    doc: "the severity: it picks the colour role, the icon, the ARIA role, and the flash lookup"
  )

  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role={status_role(@kind)}
      aria-live={status_live(@kind)}
      class="w-full"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-2xl border p-4 text-sm shadow-xl shadow-ink/[0.08] backdrop-blur",
        @kind == :success && "border-success-line bg-success-surface/95 text-success-ink",
        @kind == :info && "border-info-line bg-info-surface/95 text-info-ink",
        @kind == :warning && "border-warning-line bg-warning-surface/95 text-warning-ink",
        @kind == :error && "border-danger-line bg-danger-surface/95 text-danger-ink"
      ]}>
        <.icon name={status_icon(@kind)} class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="close" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  defp status_icon(:info), do: "information"
  defp status_icon(:success), do: "success"
  defp status_icon(:warning), do: "warning"
  defp status_icon(:error), do: "error"

  # How a status kind is announced, shared by `flash/1`, `alert/1` and
  # `panel_notice/1`: success and info are a polite `status` that waits for
  # the reader, while warning and error interrupt as an assertive `alert`.
  # `aria-live` is stated even though each role implies it, so the message
  # keeps its own politeness inside any live region that contains it.
  defp status_role(kind) when kind in [:warning, :error], do: "alert"
  defp status_role(kind) when kind in [:success, :info], do: "status"

  defp status_live(kind) when kind in [:warning, :error], do: "assertive"
  defp status_live(kind) when kind in [:success, :info], do: "polite"

  @doc """
  Renders the two connection banners for one container.

  They report a dropped or unreachable websocket, and LiveView reveals them
  from the client — the server is by definition not reachable to re-render
  when they matter. Both ids derive from `id`, so a container can carry its
  own pair without colliding with another's.

  An open modal dialog is promoted to the browser's top layer and makes the
  rest of the page inert, so the layout's pair can be neither painted above
  the dimmer, announced nor dismissed while one is open. `modal/1` renders a
  second pair inside the dialog for that reason, and the layout's is hidden
  while a dialog is open so the same banner never appears twice.

  `revealed` renders only that banner, already shown and bound to no
  connection event, so the Design Library can present what a drop looks like
  without becoming a second live outlet that would report it again.
  """
  attr(:id, :string, required: true)

  attr(:revealed, :atom,
    values: [:client, :server],
    doc: "renders only this banner, shown and unbound, for presentation"
  )

  def connection_banners(assigns) do
    assigns =
      assigns
      |> assign_new(:revealed, fn -> nil end)
      |> assign(:client_id, "#{assigns.id}-client-error")
      |> assign(:server_id, "#{assigns.id}-server-error")

    ~H"""
    <.flash
      :if={@revealed != :server}
      id={@client_id}
      kind={:error}
      title={gettext("Connection interrupted")}
      phx-disconnected={
        !@revealed &&
          show(".phx-client-error ##{@client_id}")
          |> JS.remove_attribute("hidden", to: ".phx-client-error ##{@client_id}")
      }
      phx-connected={!@revealed && hide("##{@client_id}") |> JS.set_attribute({"hidden", ""})}
      hidden={!@revealed}
    >
      {gettext("Reconnecting…")}
    </.flash>

    <.flash
      :if={@revealed != :client}
      id={@server_id}
      kind={:error}
      title={gettext("Server unavailable")}
      phx-disconnected={
        !@revealed &&
          show(".phx-server-error ##{@server_id}")
          |> JS.remove_attribute("hidden", to: ".phx-server-error ##{@server_id}")
      }
      phx-connected={!@revealed && hide("##{@server_id}") |> JS.set_attribute({"hidden", ""})}
      hidden={!@revealed}
    >
      {gettext("Attempting to reconnect")}
      <.icon name="hero-arrow-path" class="ml-1 size-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders an inline status alert (Belimbing's `x-ui.alert` counterpart).

  Kinds map to the honest status roles: `:info`, `:success`, `:warning`,
  `:error`. Success and info are announced politely as a `status`; warning
  and error interrupt as an `alert`.

  ## Examples

      <.alert kind={:warning}>Your session expired. Sign in again to continue.</.alert>
  """
  attr(:kind, :atom, values: [:info, :success, :warning, :error], default: :info)
  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def alert(assigns) do
    ~H"""
    <div
      role={status_role(@kind)}
      aria-live={status_live(@kind)}
      class={[
        "flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-sm",
        status_surface(@kind),
        @class
      ]}
      {@rest}
    >
      <.icon name={status_icon(@kind)} class="mt-0.5 size-4 shrink-0" />
      <div class="min-w-0">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  # The one inline colouring per status role, shared by `alert/1` and
  # `panel_notice/1` so a success reads as the same idea wherever it lands.
  # The page-level `flash/1` uses the same roles at banner strength.
  defp status_surface(:info), do: "border-info-line bg-info-surface text-info-ink"
  defp status_surface(:success), do: "border-success-line bg-success-surface text-success-ink"
  defp status_surface(:warning), do: "border-warning-line bg-warning-surface text-warning-ink"
  defp status_surface(:error), do: "border-danger-line bg-danger-surface text-danger-ink"

  @doc """
  Renders a panel's outcome notice: what the last action on a panel did.

  A LiveComponent panel cannot reach the page's flash without a parent
  contract, and a notice raised while one of its modal dialogs is open has
  to render inside that dialog, where the page behind is inert. The panel
  therefore holds one `{kind, message}` outcome and renders it through this
  component above its table, or inside its open dialog, and dismisses it
  through `on_dismiss`. The gap to what follows is the caller's, through
  `class`.

  `kind` is what the message does, not how it is worded: a write that
  finished says `:success`, a notice that merely informs stays `:info`, and
  a refusal or failure is `:error`. When one handler can confirm a write or
  report that nothing changed, the kind comes from that branch. A refusal
  names its real cause. A completed write and an error look like
  their page-level flash counterparts at inline strength, and so does an
  informational notice on the `info` role. Success and info are announced
  politely as a `status`; an error interrupts as an `alert`.

  ## Examples

      <.panel_notice
        :if={@notice}
        id={"\#{@id}-notice"}
        kind={elem(@notice, 0)}
        on_dismiss={JS.push("clear_notice", target: @myself)}
        class="mb-3"
      >
        {elem(@notice, 1)}
      </.panel_notice>
  """
  attr(:id, :string, required: true)

  attr(:kind, :atom,
    values: [:info, :success, :error],
    required: true,
    doc: "what the message does: a completed write, a plain statement, or a failure"
  )

  attr(:on_dismiss, JS, required: true, doc: "the command the Dismiss control runs")
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  def panel_notice(assigns) do
    ~H"""
    <div
      id={@id}
      role={status_role(@kind)}
      aria-live={status_live(@kind)}
      data-kind={@kind}
      class={[
        "flex items-start gap-2 rounded-lg border px-3 py-2 text-sm",
        status_surface(@kind),
        @class
      ]}
    >
      <.icon name={status_icon(@kind)} class="mt-0.5 size-4 shrink-0" />
      <span class="min-w-0 flex-1">{render_slot(@inner_block)}</span>
      <.icon_button
        id={"#{@id}-dismiss"}
        icon="close"
        label="Dismiss notice"
        context={:inline}
        class="-my-0.5"
        phx-click={@on_dismiss}
      />
    </div>
    """
  end

  @doc """
  Renders a compact status badge with a state dot, for entity statuses such
  as `"active"` or `"archived"`. Neutral by default; pass `kind` for a
  status color.
  """
  attr(:kind, :atom, values: [:neutral, :success, :warning, :danger], default: :neutral)
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium capitalize",
      @kind == :neutral && "bg-surface-muted text-ink-muted",
      @kind == :success && "bg-success-surface text-success-ink",
      @kind == :warning && "bg-warning-surface text-warning-ink",
      @kind == :danger && "bg-danger-surface text-danger-ink",
      @class
    ]}>
      <span class="size-1.5 rounded-full bg-current opacity-70"></span>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a compact strip of related statistics.

  A stat strip is a small dashboard surface: its title identifies the subject
  and each item supplies one label and value. Passing `navigate` makes the
  whole strip a quiet destination link; omitting it keeps the same surface
  readable when the viewer cannot open the related workflow.

  Numeric values use the larger tabular treatment by default. Pass
  `kind={:text}` for a textual value such as a storage or scope description.

  ## Examples

      <.stat_strip id="company-stats" title="Companies" navigate={~p"/companies"}>
        <:item label="Total" value={@company_count} />
        <:item label="Active" value={@active_count} />
        <:item label="Current" kind={:text} value={@current_code || "—"} />
      </.stat_strip>
  """
  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:navigate, :string, default: nil)

  slot :item, required: true do
    attr(:label, :string, required: true)
    attr(:value, :any, required: true)
    attr(:kind, :atom, values: [:number, :text])
  end

  def stat_strip(assigns) do
    assigns = assign(assigns, :linked?, is_binary(assigns.navigate))

    ~H"""
    <.link
      :if={@linked?}
      navigate={@navigate}
      id={@id}
      class="group block rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03] transition hover:border-high-contrast-line hover:bg-gradient-to-b hover:from-surface hover:to-brand-surface hover:shadow-sm"
    >
      <.stat_strip_content id={@id} title={@title} items={@item} linked={@linked?} />
    </.link>
    <div
      :if={!@linked?}
      id={@id}
      class="rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03]"
    >
      <.stat_strip_content id={@id} title={@title} items={@item} linked={@linked?} />
    </div>
    """
  end

  defp stat_strip_content(assigns) do
    assigns = assign(assigns, :item_count, length(assigns.items))

    ~H"""
    <div class="flex items-center justify-between gap-3">
      <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
        {@title}
      </p>
      <.icon
        :if={@linked}
        name="forward"
        class="size-4 shrink-0 text-brand-strong transition group-hover:translate-x-0.5"
      />
    </div>
    <div class={["mt-2.5 grid divide-x divide-line", stat_strip_columns(@item_count)]}>
      <div
        :for={{item, index} <- Enum.with_index(@items)}
        id={"#{@id}-item-#{index}"}
        class={["min-w-0", stat_strip_cell(index, @item_count)]}
      >
        <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">{item.label}</p>
        <p class={[
          "mt-1 font-semibold text-ink-strong",
          stat_strip_value_class(Map.get(item, :kind, :number))
        ]}>
          {item.value}
        </p>
      </div>
    </div>
    """
  end

  defp stat_strip_columns(1), do: "grid-cols-1"
  defp stat_strip_columns(2), do: "grid-cols-2"
  defp stat_strip_columns(_count), do: "grid-cols-3"

  defp stat_strip_cell(0, 1), do: "px-0"
  defp stat_strip_cell(0, count) when count > 1, do: "pr-3"
  defp stat_strip_cell(index, count) when index == count - 1, do: "pl-3"
  defp stat_strip_cell(_index, _count), do: "px-3"

  defp stat_strip_value_class(:text), do: "truncate text-sm"
  defp stat_strip_value_class(_kind), do: "text-xl tabular-nums"

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
      <.button type="submit" busy={@saving}>Saving…</.button>

  ## In-flight state

  A control that has been activated and is waiting for its outcome is
  `busy`: it spins, stays at full strength, and renders `aria-busy="true"`
  and `disabled`, so the wait is visible, is heard by assistive technology,
  and cannot be started twice. Plain `disabled` dims and never spins, so
  "not available" never reads as "working". The caller keeps the label
  truthful ("Saving…", "Opening workspace…").

  `busy` is a button state. It is carried by `disabled`, which an anchor has
  no equivalent of, so a control rendered as a link ignores `busy` entirely
  rather than announcing a wait it cannot prevent a second activation of.

  `busy` is the server-known wait that outlives one round trip, such as the
  sign-in handoff that arms a full form submission. The shorter wait of one
  `phx-click` or `phx-submit` round trip stays `phx-disable-with`'s job:
  LiveView disables the control and swaps its label, and `app.js` mirrors
  LiveView's own loading state onto `aria-busy` while it lasts. That path is
  announced but not spun: it still wears the dimmed disabled treatment.
  """
  attr(:rest, :global, include: ~w(href navigate patch method download name value disabled type))

  attr(:class, :any)
  attr(:variant, :string, values: ~w(primary danger))

  attr(:busy, :boolean,
    default: false,
    doc:
      "the control was activated and is waiting; renders `aria-busy` and disables it. " <>
        "A button state: a link cannot be disabled, so `busy` is ignored on one."
  )

  slot(:inner_block, required: true)

  def button(%{rest: rest} = assigns) do
    assigns = assign(assigns, :busy, assigns.busy and not link?(rest))

    # Each variant owns every color property it sets, including the focus ring;
    # a color defined in both the shared base and a variant is resolved by
    # stylesheet order, not by this list's order (#619's invisible button).
    variants = %{
      "primary" =>
        "bg-action text-action-ink hover:bg-action-hover shadow-sm focus-visible:ring-brand-strong/30",
      "danger" =>
        "text-danger hover:bg-danger-surface hover:text-danger-ink hover:underline " <>
          "focus-visible:ring-brand-strong/30",
      nil =>
        "border border-high-contrast-line bg-surface text-ink hover:bg-surface-sunken shadow-sm " <>
          "focus-visible:ring-brand-strong/30"
    }

    # A caller-supplied class extends the button; it must not replace the
    # variant, or `<.button variant="primary" class="w-full">` silently
    # renders an unstyled button.
    assigns =
      assigns
      |> assign(:class, [
        "inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold",
        "transition focus-visible:outline-none focus-visible:ring-2",
        "focus-visible:ring-offset-2 focus-visible:ring-offset-canvas",
        if(assigns.busy,
          do: "cursor-progress",
          else: "disabled:cursor-not-allowed disabled:opacity-50"
        ),
        Map.fetch!(variants, assigns[:variant]),
        assigns[:class]
      ])
      |> assign(:rest, busy_rest(rest, assigns.busy))

    if link?(rest) do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} aria-busy={@busy && "true"} {@rest}>
        <.icon :if={@busy} name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  defp link?(rest), do: !!(rest[:href] || rest[:navigate] || rest[:patch])

  # An async action rejects duplicate work. A busy control is also disabled:
  # the activation that made it busy is the one whose outcome is pending, and
  # a second one would duplicate the work. `button/1` and `icon_button/1` both
  # pass through here.
  # A link cannot be disabled, so `busy` is already resolved to false on one
  # and never reaches here.
  defp busy_rest(rest, false), do: rest
  defp busy_rest(rest, true), do: Map.put(rest, :disabled, true)

  @doc """
  Renders a compact icon-only action.

  Use `context={:inline}` beside a heading or label, and the default
  `context={:table}` for repeated table and toolbar actions. Icon-only actions
  are for familiar operations where the label is still available to assistive
  technology and as a tooltip. Keep primary or unfamiliar actions as text
  buttons.

  `disabled` and `busy` follow `button/1`: a disabled action is not available
  and dims, a busy one was activated and is waiting for its outcome, so it
  sits in a sunken ringed well and its glyph becomes a spinner at full
  strength. The well and the swapped glyph are static, so the states stay
  distinguishable under `prefers-reduced-motion`, where the spin itself does
  not render. Both are inert; only the busy one carries `aria-busy`, and its
  label still names the action so assistive technology can say what is
  pending. `busy` is a button state here too, and is ignored on a link.

  `phx-disable-with` does not belong here. LiveView implements it by replacing
  the control's text, which on an icon-only action deletes the glyph and
  restores an empty string, leaving an empty well behind. Use `busy` for a
  wait the server knows about; a plain one-round-trip `phx-click` needs no
  adornment.
  """
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:context, :atom, values: [:inline, :table], default: :table)
  attr(:kind, :atom, values: [:neutral, :danger], default: :neutral)
  attr(:class, :any, default: nil)

  attr(:chrome, :atom,
    values: [:utilities, :nav],
    default: :utilities,
    doc:
      "`:nav` is the sidebar pin and tile control. It renders `nav-icon-button` " <>
        "from `apps/web/assets/css/app.css` instead of repeating that utility list " <>
        "on every button. Other icon buttons keep `:utilities`."
  )

  attr(:busy, :boolean,
    default: false,
    doc:
      "the action was activated and is waiting; renders `aria-busy` and disables it. " <>
        "A button state: a link cannot be disabled, so `busy` is ignored on one."
  )

  attr(:rest, :global,
    include: ~w(href navigate patch method download disabled type name value title),
    doc:
      "`phx-disable-with` is incompatible with an icon-only action: LiveView " <>
        "implements it by replacing the control's text content, which deletes the " <>
        "glyph and restores an empty string. Use `busy` instead."
  )

  def icon_button(%{rest: rest} = assigns) do
    assigns = assign(assigns, :busy, assigns.busy and not link?(rest))

    assigns =
      assigns
      |> assign(:control_class, icon_button_class(assigns))
      |> assign(:icon_name, if(assigns.busy, do: "hero-arrow-path", else: assigns.icon))
      |> assign(:icon_class, [
        if(assigns.context == :inline, do: "size-3.5", else: "size-4"),
        assigns.busy && "motion-safe:animate-spin"
      ])
      |> assign(:title, rest[:title] || assigns.label)
      |> assign(:control_type, rest[:type] || "button")
      |> assign(
        :control_rest,
        rest |> Map.drop([:title, :type]) |> busy_rest(assigns.busy)
      )

    if link?(rest) do
      ~H"""
      <.link aria-label={@label} title={@title} class={@control_class} {@control_rest}>
        <.icon name={@icon_name} class={@icon_class} />
      </.link>
      """
    else
      ~H"""
      <button
        type={@control_type}
        aria-label={@label}
        aria-busy={@busy && "true"}
        title={@title}
        class={@control_class}
        {@control_rest}
      >
        <.icon name={@icon_name} class={@icon_class} />
      </button>
      """
    end
  end

  # The sidebar repeats this control on every destination. The long utility
  # list used to be written out on each one (`nav-icon-button` in app.css is
  # that list, once). Busy and danger keep the explicit utilities: the nav
  # treatment has neither.
  defp icon_button_class(%{chrome: :nav, busy: false, kind: :neutral} = assigns) do
    ["nav-icon-button", assigns.class]
  end

  defp icon_button_class(assigns) do
    [
      "grid shrink-0 place-items-center transition focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
      assigns.context == :inline && "size-6 rounded-sm",
      assigns.context == :table && "size-7 rounded-md",
      assigns.kind == :neutral && "text-ink-muted hover:bg-surface-sunken hover:text-ink",
      assigns.kind == :danger && "text-danger hover:bg-danger-surface hover:text-danger-ink",
      if(assigns.busy,
        do: "cursor-progress bg-surface-sunken ring-1 ring-line",
        else: "disabled:text-ink-faint disabled:cursor-not-allowed disabled:opacity-50"
      ),
      assigns.class
    ]
  end

  @doc """
  Renders a timestamp honoring the process display context (#459).

  Compatible source timestamps are stored as UTC `NaiveDateTime` values and
  are explicitly interpreted as UTC. The mode comes from the per-process
  `Bilimbi.Base.UI.DateTimeDisplay` context the web edge resolved (or the
  `display` attr when a caller carries it explicitly):

    * `:local` — the server-rendered text stays truthful, labelled UTC, and
      the `DateTime` hook enhances it into the browser's time zone.
    * `:company` — the server shifts into the company IANA zone through the
      database module the context carries and renders text labelled with the
      zone abbreviation. A zone that cannot convert falls back to the
      truthful UTC text rather than guessing.
    * `:utc` — the server renders the stored UTC value.

  ## Following a mode change already on screen

  A saved shell mode must reach instants that are already rendered, including
  rows handed to the DOM by a LiveView stream, which the server never
  re-renders. So the element carries the server's own text for both modes the
  server can decide — `data-text-company` and `data-text-utc` — and the
  `DateTime` hook swaps to the matching one when `#app-shell` publishes a new
  `data-display-mode`. For those two modes the browser copies a server string
  and never formats one, so the two renderings cannot disagree.

  `:local` is the one mode the server cannot decide, because it does not know
  the browser's zone. The hook formats it in the reader's own locale and hour
  cycle, the way their device would (see `date_time.js`).

  The mechanism lives here rather than at the call sites, so a `<.datetime>`
  added later follows a mode change without its author knowing the mechanism
  exists. An instant given an explicit `display` is pinned to that context
  instead, because its caller has already decided what it is showing.

  With no context stored, `:local` — the pre-policy behavior, and the
  truthful no-JavaScript fallback in every mode is the server text itself.

  A time of day shows minutes. `precision={:second}` adds seconds, for a
  reader who compares two instants that can fall inside one minute.
  """
  attr(:id, :string, required: true)
  attr(:value, :any, default: nil)
  attr(:format, :atom, values: [:date, :time, :datetime], default: :datetime)
  attr(:precision, :atom, values: [:minute, :second], default: :minute)
  attr(:class, :any, default: nil)

  attr(:display, :any,
    default: nil,
    doc: "explicit display context that pins the instant to it; defaults to the process context"
  )

  # Every timestamp a person reads goes through here, so a saved clock
  # change reaches instants already on screen. Pass `precision={:second}`
  # when two events in one minute must stay distinct (an audit diff).
  # Do not format the instant in the template. `display` pins one instant;
  # omit it to follow the reader's clock.
  def datetime(assigns) do
    display = assigns.display || Bilimbi.Base.UI.DateTimeDisplay.get()
    date_time = datetime_value(assigns.value)
    mode = display_mode(display)
    format = {assigns.format, assigns.precision}

    # Both server-decidable modes are rendered up front, whatever the current
    # mode is, so the browser can follow a mode change by copying a server
    # string instead of formatting one of its own.
    text_company = date_time && policy_datetime(date_time, format, :company, display)
    text_utc = date_time && server_datetime(date_time, format)

    assigns =
      assigns
      |> assign(:date_time, date_time)
      |> assign(:date, date_value(assigns.value))
      |> assign(:mode, mode)
      |> assign(:text_company, text_company)
      |> assign(:text_utc, text_utc)
      # The mode's own text is always one of the two above rather than a third
      # rendering: `:company` is `text_company`, and both `:local` and `:utc`
      # delegate to `server_datetime/2`, which is `text_utc`. Picking avoids a
      # third formatting pass per timestamp — and in `:company`, the product
      # default, a second `DateTime.shift_zone/3` through the time zone
      # database on every timestamp of every row.
      |> assign(:text, if(mode == :company, do: text_company, else: text_utc))

    ~H"""
    <%!-- A calendar date is a zone-free fact: converting it through the
         company/local display modes could shift the day, so a %Date{}
         renders as-is with no mode logic and no zone suffix (#619). --%>
    <time :if={@date} id={@id} datetime={Date.to_iso8601(@date)} class={["tabular-nums", @class]}>
      {Calendar.strftime(@date, "%d/%m/%Y")}
    </time>
    <%!-- `phx-update="ignore"` is deliberately absent: the server has to be
         able to refresh these strings when the value or the company zone
         changes, and the hook re-applies the current mode on every patch. --%>
    <time
      :if={@date_time}
      id={@id}
      datetime={DateTime.to_iso8601(@date_time)}
      data-format={@format}
      data-precision={@precision}
      data-mode={@mode}
      data-text-company={@text_company}
      data-text-utc={@text_utc}
      data-follow-shell={is_nil(@display) && "true"}
      phx-hook="DateTime"
      class={["tabular-nums", @class]}
    >
      {@text}
    </time>
    <span :if={is_nil(@date_time) and is_nil(@date)} id={@id} class={@class}>—</span>
    """
  end

  defp datetime_value(%DateTime{} = value), do: value
  defp datetime_value(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp datetime_value(_value), do: nil

  defp date_value(%Date{} = value), do: value
  defp date_value(_value), do: nil

  defp display_mode(%{mode: mode}) when mode in [:company, :local, :utc], do: mode
  defp display_mode(_display), do: :local

  defp policy_datetime(value, format, :company, display) do
    with %{timezone: timezone, tz_db: tz_db} when is_binary(timezone) and is_atom(tz_db) <-
           display,
         {:ok, shifted} <- DateTime.shift_zone(value, timezone, tz_db) do
      zoned_datetime(shifted, format)
    else
      # An unconvertible zone or an incomplete context renders the truthful
      # stored value instead of a wrong local-looking one.
      _other -> server_datetime(value, format)
    end
  end

  defp server_datetime(value, format), do: Calendar.strftime(value, strftime(format)) <> " UTC"

  defp zoned_datetime(value, format),
    do: Calendar.strftime(value, strftime(format)) <> " " <> value.zone_abbr

  defp strftime({:date, _precision}), do: "%d/%m/%Y"
  defp strftime({:time, precision}), do: clock(precision)
  defp strftime({:datetime, precision}), do: "%d/%m/%Y, " <> clock(precision)

  defp clock(:minute), do: "%H:%M"
  defp clock(:second), do: "%H:%M:%S"

  @doc """
  Renders a card container with a subtle border (Belimbing's `x-ui.card` counterpart).

  The body pads itself with `p-2` unless `inner_class` sets a padding of its
  own. A padding shorthand the caller passes (`p-0`, `p-3`, `p-5 sm:p-6`)
  replaces the default outright, resolved here before the classes reach the
  markup: two utilities of equal specificity are decided by their order in
  the generated stylesheet, where `.p-0` is emitted before `.p-2`, so a
  caller that merely appended `p-0` would still render 8px. An axis-only
  class (`px-4`, `px-3 py-2`) keeps the default on the axis it leaves alone,
  exactly as the cascade already renders it. The same convention as
  `field_class/4`: what the caller states replaces what the component would
  have assumed.

  `inner_class` carrying `p-0` is also the flat-corner signal. It is what
  every list-page card passes — a card framing a table and its pager, the
  full-bleed case where the card edge is the table's frame — so the card
  reads it to drop the radius: a table must not pick up a corner from the
  frame around it. This is the only place that decision is made, which is
  why no list screen passes a corner class of its own. Any other card keeps
  its radius.

  `data-card` marks the card for the "list fill" rules in `app.css`, which
  let a card that frames a table shrink with a workspace tile.
  """
  attr(:id, :string, default: nil)
  attr(:title, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:inner_class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def card(assigns) do
    tokens = class_tokens(assigns.inner_class)

    assigns =
      assigns
      |> assign(:flat, "p-0" in tokens)
      |> assign(:inner_padding, inner_padding(tokens))

    ~H"""
    <div
      id={@id}
      data-card
      class={[!@flat && "rounded-xl", "border border-line bg-surface shadow-xs", @class]}
      {@rest}
    >
      <div :if={@title} class="border-b border-line px-4 py-3">
        <h3 class="text-base font-semibold text-ink">{@title}</h3>
      </div>
      <div class={[@inner_padding, @inner_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp class_tokens(class) do
    class
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.flat_map(&String.split(to_string(&1)))
  end

  # The caller's padding shorthand wins over the `p-2` default. Resolve
  # that here: two utilities of equal specificity follow stylesheet order,
  # and `.p-0` is emitted before `.p-2`, so appending the caller's class
  # would still render 8px. A responsive shorthand (`sm:p-6`) sets nothing
  # below its breakpoint, and an axis-only one (`px-4`) sets nothing on
  # the other axis, so both keep the default where they say nothing.
  defp inner_padding(tokens) do
    if Enum.any?(tokens, &match?("p-" <> _, &1)), do: nil, else: "p-2"
  end

  @doc """
  Renders a modal dialog over the current screen.

  The caller decides whether the dialog exists: render it with `:if` while
  the workflow it hosts is in progress and stop rendering it when that
  workflow ends. While it exists the browser owns modal behaviour through a
  native `<dialog>`: focus moves inside on open and stays inside, the page
  behind is inert to the keyboard and to assistive technology, and Escape
  asks to close. The `Modal` hook promotes the dialog to modal on mount,
  forwards Escape to `on_cancel`, and returns focus to the control that
  opened the dialog once the server has removed it.

  `on_cancel` must reach the same handler as the Cancel button, so Escape
  and Cancel are one action. Clicking the dimmed page does nothing: a dialog
  usually holds a form, and a stray click must not discard it.

  The dialog is named by its title and, when given, described by its
  description, so a screen reader announces both when focus enters.

  A LiveView that can raise a flash while its dialog stays open passes
  `flash`. The page behind a modal dialog is inert, so the layout's flash
  group can be neither read nor dismissed while one is open; the dialog
  renders its own copy instead, and the layout's copy is hidden.

  The dialog also carries its own `connection_banners/1`, because the page
  behind it is inert and painted under the dimmer: a dropped websocket must
  still be announced and dismissable while a dialog is open.

  Every production caller dismisses the layout flash as it opens a dialog, so
  a message about finished work is neither adopted as the new dialog's own
  feedback nor stranded unreadable behind the inert page. A LiveView does that
  in the handler that opens the dialog; a LiveComponent cannot reach the
  page's flash, so its opening control pushes `lv:clear-flash` untargeted
  before the open event. The Design Library specimen deliberately clears
  nothing: it raises no flash of its own, so there is none of its own to
  dismiss.

  ## Examples

      <.modal
        :if={@show_attach_modal}
        id="attach-address-modal"
        title="Attach Address"
        on_cancel={JS.push("close_attach_modal", target: @myself)}
      >
        <:description>Select an address to attach to this company.</:description>
        <.form for={@attach_form} id="attach-address-modal-form" ...>
          ...
        </.form>
      </.modal>
  """
  attr(:id, :string, required: true)
  attr(:title, :string, required: true)

  attr(:on_cancel, JS,
    required: true,
    doc: "the command run when the user asks to close, the same push as the Cancel button"
  )

  attr(:width, :atom,
    values: [:compact, :narrow, :wide],
    default: :narrow,
    doc:
      "`:narrow` for a single-column form, `:wide` for a two-column one, " <>
        "`:compact` for a confirmation that holds no form"
  )

  attr(:flash, :map,
    default: nil,
    doc: "the caller's flash, rendered inside the dialog because the page behind it is inert"
  )

  attr(:rest, :global)
  slot(:description, doc: "one short line under the title, announced with the dialog")
  slot(:inner_block, required: true)

  def modal(assigns) do
    ~H"""
    <dialog
      id={@id}
      open
      phx-hook="Modal"
      data-cancel={@on_cancel}
      data-owns-flash={@flash != nil}
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      aria-describedby={@description != [] && "#{@id}-description"}
      tabindex="-1"
      class={[
        "mx-auto mt-16 mb-4 max-h-[calc(100%-5rem)] w-[calc(100%-2rem)] overflow-y-auto",
        "rounded-xl border border-line bg-surface p-6 text-ink shadow-lg",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong/30",
        "backdrop:bg-ink/40",
        @width == :compact && "max-w-md",
        @width == :narrow && "max-w-lg",
        @width == :wide && "max-w-2xl"
      ]}
      {@rest}
    >
      <h2 id={"#{@id}-title"} class="text-lg font-medium tracking-tight text-ink-strong">
        {@title}
      </h2>
      <.flash :if={@flash} kind={:error} id={"#{@id}-flash-error"} flash={@flash} />
      <.flash :if={@flash} kind={:info} id={"#{@id}-flash-info"} flash={@flash} />
      <.connection_banners id={@id} />
      <p :if={@description != []} id={"#{@id}-description"} class="mt-1 text-xs text-ink-subtle">
        {render_slot(@description)}
      </p>
      {render_slot(@inner_block)}
    </dialog>
    """
  end

  @doc """
  Renders a confirmation for an action that cannot be undone.

  A confirmation is a `modal/1` that leads with the consequence, not with the
  question. `consequence` is the dialog's title and so its accessible name —
  "Legal entity type “LLC” will be deleted." — so it is the first thing a
  sighted person reads and the first thing a screen reader announces; `detail`
  says what is kept and whether the change can be undone, and is announced as
  the description. Both are complete sentences. The dialog is an
  `alertdialog`, the role assistive technology reserves for a message that
  needs an answer before anything else continues.

  Two actions and nothing else. Cancel comes first, so it takes focus when the
  dialog opens and Enter, Escape and Cancel all keep the data as it is; the
  confirm follows as a calm danger text control named by the verb alone
  ("Delete", "Unlink"), because the consequence has already said what will
  happen. Nobody retypes a name to prove they read the sentence above the
  button: there is no typed acknowledgement.

  The caller owns the dialog's existence exactly as for `modal/1`: render it
  with `:if` while a request is pending, run the action from `on_confirm`, and
  stop rendering it whatever the outcome. The outcome then reports through the
  page's flash or the panel's notice, as any other write does, and a refusal
  says what to do next. The confirm carries `phx-disable-with={@working}` for
  the round trip, so it reads "Deleting…", is announced busy, and stays
  disabled until the server replies, so a second click cannot repeat the
  action.

  ## Examples

      <.confirm_dialog
        :if={@pending_delete}
        id="delete-type-confirm"
        consequence={"Legal entity type “\#{@pending_delete.name}” will be deleted."}
        detail="It can no longer be chosen for a company. This cannot be undone."
        confirm="Delete"
        working="Deleting…"
        on_confirm={JS.push("delete")}
        on_cancel={JS.push("cancel_delete")}
      />
  """
  attr(:id, :string, required: true)

  attr(:consequence, :string,
    required: true,
    doc: "what will happen to the data, as one sentence; the dialog's title and accessible name"
  )

  attr(:detail, :string,
    required: true,
    doc: "what is kept and whether the change can be undone; announced as the description"
  )

  attr(:confirm, :string,
    required: true,
    doc: ~s(the verb on the danger action, such as "Delete")
  )

  attr(:working, :string,
    required: true,
    doc: ~s(the confirm's label while the round trip is in flight, such as "Deleting…")
  )

  attr(:on_confirm, JS, required: true, doc: "the command that performs the action")

  attr(:on_cancel, JS,
    required: true,
    doc: "the command that closes the dialog without acting; Escape runs the same one"
  )

  attr(:rest, :global)

  # Never `data-confirm`. The caller holds the record, renders this while
  # that record is pending, and stops rendering it whatever the outcome.
  def confirm_dialog(assigns) do
    ~H"""
    <.modal
      id={@id}
      title={@consequence}
      width={:compact}
      on_cancel={@on_cancel}
      role="alertdialog"
      {@rest}
    >
      <:description>{@detail}</:description>
      <div class="mt-5 flex flex-wrap justify-end gap-2">
        <.button id={"#{@id}-cancel"} type="button" phx-click={@on_cancel}>
          Cancel
        </.button>
        <.button
          id={"#{@id}-confirm"}
          type="button"
          variant="danger"
          phx-click={@on_confirm}
          phx-disable-with={@working}
        >
          {@confirm}
        </.button>
      </div>
    </.modal>
    """
  end

  @doc """
  Renders the page content container at the width of its workflow kind.

  Every screen is one of three kinds, and the width is chosen here and
  nowhere else (#287). Variation between same-kind screens has no
  user-visible reason, which is what DESIGN.md's *Stay consistent* forbids.

    * `:list` — operational index screens with tables and filters, at
      `max-w-7xl`. The densest tables (seven columns) need the room; a
      sparse table's trailing whitespace is benign, while a cramped dense
      table forces the navigation *Compact layout* asks us to avoid.
    * `:form` — single-column edit forms, at `max-w-2xl`.
    * `:detail` — show screens and the dashboard, at the list width
      `max-w-7xl`. Belimbing gives a detail page the same column as a list:
      its `admin/*/show` pages set no width of their own, so their cards
      fill the main area beside the sidebar at every viewport. A detail's
      sections carry the same tables an index does (a user's employee
      records, a company's addresses), so it takes the same room, and the
      layout no longer jumps between `/users` and `/users/1`. The cap only
      binds on a column wider than 80rem, where Bilimbi's lists already
      stop; prose inside a section keeps its own reading limit.

  ## Examples

      <.page id="users-index">
        ...
      </.page>

      <.page variant={:form}>
        ...
      </.page>

  `data-page` names the variant for the stylesheet. Inside a workspace tile
  a `:list` page whose table would run past the tile keeps its heading and
  pager in sight and scrolls the table instead; the "list fill" rules in
  `apps/web/assets/css/app.css` own that, and they start from this element.
  """
  attr(:id, :string, default: nil)
  attr(:variant, :atom, default: :list, values: [:list, :form, :detail])
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <div id={@id} data-page={@variant} class={["mx-auto", page_width(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp page_width(:list), do: "max-w-7xl"
  defp page_width(:form), do: "max-w-2xl"
  defp page_width(:detail), do: "max-w-7xl"

  @doc """
  Renders a header with title.

  With `actions`, the title block and the actions row share one line from
  the `sm` breakpoint and stack — title first, actions below — on a phone,
  as Belimbing's `x-ui.page-header` does, so a labelled actions row never
  squeezes the title into one word per line or clips at the viewport edge.

  Inside a workspace tile the header leaves its top right corner to the
  tile's floating controls (`tile_controls/1`): `app.css` pads the element
  marked `data-page-header` there, so an action never sits under them.
  """
  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:title_actions)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header
      data-page-header
      class={[
        @actions != [] &&
          "flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-6",
        "pb-4"
      ]}
    >
      <div>
        <div :if={@title_actions != []} class="flex items-center gap-1.5">
          <h1 class="text-lg font-semibold leading-8 tracking-tight text-action">
            {render_slot(@inner_block)}
          </h1>
          {render_slot(@title_actions)}
        </div>
        <h1
          :if={@title_actions == []}
          class="text-lg font-semibold leading-8 tracking-tight text-action"
        >
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-ink-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="sm:flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a compact tab strip for sibling views of the same page.

  The selected tab uses the lime `brand-strong` underline. Unselected tabs stay
  muted and darken on hover.

  A tab that carries `href` or `patch` renders as a link; one that carries
  `click` renders as a button so in-page switching still works.

  The labels stay on one line. The strip's inline size ignores those labels
  (`contain-inline-size`), so a card or grid cannot grow to fit them; what
  does not fit scrolls inside the strip. `TabStrip`
  (`apps/web/assets/js/tab_strip.js`) shows an edge control only while a tab
  sits outside the strip, keeps those controls out of tab order, and scrolls
  a focused tab clear of the edge.

  ## Examples

      <.tabs id="example-tabs" aria-label="Example views">
        <:tab href="#overview" current>Overview</:tab>
        <:tab href="#history">History</:tab>
      </.tabs>
  """
  attr(:id, :string, required: true)
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot :tab, required: true do
    attr(:id, :string)
    attr(:href, :string)
    attr(:patch, :string)
    attr(:current, :boolean)
    attr(:click, :string)
    attr(:value, :string)
  end

  def tabs(assigns) do
    ~H"""
    <nav
      id={@id}
      class={["relative w-full min-w-0 max-w-full contain-inline-size", @class]}
      phx-hook="TabStrip"
      {@rest}
    >
      <div
        id={"#{@id}-scroller"}
        data-tab-scroller
        class="flex w-full min-w-0 max-w-full flex-nowrap gap-1 overflow-x-auto overscroll-x-contain scroll-px-8 border-b border-line [scrollbar-width:thin]"
      >
        <.tab_item :for={tab <- @tab} tab={tab} />
      </div>
      <button
        type="button"
        id={"#{@id}-scroll-start"}
        data-tab-scroll="start"
        tabindex="-1"
        hidden
        aria-label="Show earlier tabs"
        class="absolute top-1/2 left-0 z-10 grid size-6 -translate-y-1/2 place-items-center text-ink-muted"
      >
        <.icon name="hero-chevron-left" class="size-4" />
      </button>
      <button
        type="button"
        id={"#{@id}-scroll-end"}
        data-tab-scroll="end"
        tabindex="-1"
        hidden
        aria-label="Show later tabs"
        class="absolute top-1/2 right-0 z-10 grid size-6 -translate-y-1/2 place-items-center text-ink-muted"
      >
        <.icon name="hero-chevron-right" class="size-4" />
      </button>
    </nav>
    """
  end

  attr(:tab, :map, required: true)

  defp tab_item(assigns) do
    tab = assigns.tab
    linked? = is_binary(tab[:href]) or is_binary(tab[:patch])

    assigns =
      assigns
      |> assign(:linked?, linked?)
      |> assign(:tab_class, tab_class(tab))

    ~H"""
    <.link
      :if={@linked?}
      href={@tab[:href]}
      patch={@tab[:patch]}
      id={@tab[:id]}
      data-tab
      class={@tab_class}
      aria-current={@tab[:current] && "page"}
    >
      {render_slot(@tab)}
    </.link>
    <button
      :if={not @linked?}
      type="button"
      id={@tab[:id]}
      data-tab
      class={@tab_class}
      aria-current={@tab[:current] && "page"}
      phx-click={@tab[:click]}
      phx-value-tab={@tab[:value]}
    >
      {render_slot(@tab)}
    </button>
    """
  end

  defp tab_class(tab) do
    current? = tab[:current] == true

    [
      "-mb-px shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm transition",
      "focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
      current? && "border-brand-strong font-medium text-ink-strong",
      not current? && "border-transparent text-ink-muted hover:text-ink"
    ]
  end

  @doc """
  Renders an inline-editable text value (Belimbing inline-edit pattern).

  In display mode, shows the text with a pencil icon that appears on hover.
  Clicking immediately reveals an input box. Enter or leaving the field
  commits the change and pushes `@save_event` with
  `%{id: @id_value, <@name>: new_value}` to the LiveComponent that rendered
  the field, or to the LiveView when no component did (the hook addresses the
  event to its own element); Escape cancels and reverts to the
  original value without pushing. An unchanged value pushes nothing, and an
  emptied value pushes nothing unless the owner passes `allow_empty`, so a
  field that may legitimately be blank has to say so.

  An empty value reads as an em dash. A control that adds rather than edits —
  the company page's "Add activity", whose value is always empty — passes
  `placeholder`, which the trigger shows in place of the dash and the input
  repeats as its own placeholder, so the affordance says what committing it
  does.

  The displayed text is always the server's: the hook never paints the typed
  value, so a failed save leaves the stored value on screen. While the save is
  in flight the hook marks the field `aria-busy` and reveals the "Saving…"
  text; the reply patch renders the outcome the owner passes as `status`:

    * `nil` — nothing to report;
    * `:saved` — the last commit was stored;
    * `{:error, message}` — the last commit was refused, and `message` says
      why, naming the rejected value where that helps. It renders as an alert
      on this field, so validation reaches the operator where they typed.

  `Bilimbi.Base.UI.CommitStatus` records these outcomes and owns the rules
  around them; the owner passes what it recorded as `status`.

  ## Examples

      <.inline_edit
        id={"country-\#{country.id}-name"}
        value={country.country}
        id_value={country.id}
        save_event="save-country-name"
        name="country"
        label="Country name"
      />

      <.inline_edit
        id="address-label"
        value={@address.label || ""}
        name="label"
        label="Label"
        allow_empty
        status={@field_status["label"]}
        save_event="save_field"
      />
  """
  attr(:id, :string, required: true)
  attr(:value, :string, required: true)
  attr(:id_value, :any, default: nil)
  attr(:save_event, :string, default: "save")
  attr(:name, :string, default: "value")
  attr(:label, :string, default: "Edit value")

  attr(:allow_empty, :boolean,
    default: false,
    doc: "an emptied input is a real edit and pushes the empty string"
  )

  attr(:placeholder, :string,
    default: nil,
    doc: "what the trigger says while the value is empty, in place of the em dash"
  )

  attr(:status, :any,
    default: nil,
    doc: "the outcome of the last commit: `nil`, `:saved`, or `{:error, message}`"
  )

  attr(:class, :any, default: nil)
  attr(:input_class, :any, default: nil)
  attr(:rest, :global)

  # A record page edits the fact here. There is no separate Edit button,
  # and no `/:id/edit` route for a record whose only page was a form.
  # The outcome text is `Bilimbi.Base.UI.CommitStatus`, passed as `status`.
  def inline_edit(assigns) do
    assigns = assign(assigns, :status, normalize_commit_status(assigns.status))

    ~H"""
    <div
      id={@id}
      phx-hook="InlineEdit"
      data-id={@id_value || @id}
      data-field={@name}
      data-save-event={@save_event}
      data-allow-empty={@allow_empty && ""}
      class={["relative min-w-0 max-w-full text-sm text-ink", @class]}
      {@rest}
    >
      <button
        type="button"
        data-role="trigger"
        aria-label={@label}
        aria-describedby={@status && "#{@id}-status"}
        class="group flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 -mx-1.5 text-left hover:bg-surface-sunken transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
      >
        <span :if={@value != ""} data-role="text" class="text-ink">{@value}</span>
        <span :if={@value == ""} data-role="text" class="text-ink-muted">
          {@placeholder || "—"}
        </span>
        <.icon
          name="edit"
          class="size-3.5 text-ink-muted opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 transition-opacity"
        />
      </button>

      <input
        data-role="input"
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@label}
        aria-invalid={match?({:error, _}, @status) && "true"}
        class={[
          "absolute left-0 top-0 hidden w-full min-w-0 max-w-full box-border rounded border border-brand-strong bg-surface px-1.5 py-0.5 -mx-1.5 text-sm text-ink focus:outline-none focus:border-brand-strong focus:ring-1 focus:ring-brand-strong/30",
          @input_class
        ]}
      />

      <span data-role="saving" class="hidden mt-0.5 flex items-center gap-1 text-xs text-ink-muted">
        <.icon name="refresh" class="size-3 motion-safe:animate-spin" /> Saving…
      </span>

      <.commit_status id={"#{@id}-status"} status={@status} />
    </div>
    """
  end

  @doc """
  Renders a read-first choice fact with a shared edit-in-place lifecycle.

  The display slot remains the server-rendered value. An editable fact swaps it
  for the caller's select or combobox editor, which owns its form and commit
  event. Escape and blur cancellation therefore have one consistent shell,
  while the owner keeps control of its option vocabulary and business rules.
  """
  attr(:id, :string, required: true)
  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:editing, :boolean, required: true)
  attr(:editable?, :boolean, required: true)
  attr(:status, :any, required: true)
  attr(:status_id, :string, default: nil)

  slot(:display, required: true)
  slot(:editor, required: true)

  def inline_choice(assigns) do
    assigns =
      assigns
      |> assign(:status_id, assigns.status_id || "#{assigns.id}-status")
      |> assign(:status, normalize_commit_status(assigns.status))

    ~H"""
    <button
      :if={@editable? and not @editing}
      type="button"
      id={"#{@id}-display"}
      phx-click="edit_field"
      phx-value-field={@field}
      aria-label={@label}
      aria-describedby={@status && @status_id}
      class="group -mx-1.5 flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 text-left transition-colors hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
    >
      {render_slot(@display)}
      <.icon
        name="edit"
        class="size-3.5 shrink-0 text-ink-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
      />
    </button>

    <%!-- The editor may not hold focus while LiveView mounts it. Window Escape
         keeps cancellation reliable, and the editor's blur binding closes it
         when focus leaves the control. --%>
    <div
      :if={@editable? and @editing}
      phx-window-keydown="cancel_edit_field"
      phx-key="Escape"
    >
      {render_slot(@editor)}
    </div>

    <span :if={not @editable?}>{render_slot(@display)}</span>
    <.commit_status id={@status_id} status={@status} />
    """
  end

  @doc """
  Renders a read-first long-text fact with a shared edit-in-place lifecycle.

  The stored value remains visible until the owner confirms a commit. The
  textarea commits on blur, cancels on Escape, and leaves field validation and
  persistence to its owning LiveView. Use it for multi-line facts, not as a
  document or rich-text editor.
  """
  attr(:id, :string, required: true)
  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:id_value, :any, default: nil)
  attr(:editing, :boolean, required: true)
  attr(:editable?, :boolean, required: true)
  attr(:save_event, :string, required: true)
  attr(:edit_event, :string, default: "edit_field")
  attr(:cancel_event, :string, default: "cancel_edit_field")
  attr(:allow_empty, :boolean, default: false)
  attr(:rows, :integer, default: 4)
  attr(:autofocus, :boolean, default: true)
  attr(:status, :any, required: true)
  attr(:class, :any, default: nil)
  attr(:input_class, :any, default: nil)

  def inline_long_text(assigns) do
    assigns = assign(assigns, :status, normalize_commit_status(assigns.status))

    ~H"""
    <div
      id={@id}
      phx-hook="InlineLongText"
      data-id={@id_value || @id}
      data-value={@value}
      data-field={@field}
      data-save-event={@save_event}
      data-cancel-event={@cancel_event}
      data-allow-empty={@allow_empty && ""}
      class={["relative min-w-0 max-w-full text-sm text-ink", @class]}
    >
      <button
        :if={@editable? and not @editing}
        id={"#{@id}-display"}
        type="button"
        data-role="trigger"
        phx-click={@edit_event}
        phx-value-field={@field}
        aria-label={@label}
        aria-describedby={@status && "#{@id}-status"}
        class="group -mx-1.5 flex min-h-8 max-w-full min-w-0 cursor-pointer items-start gap-1.5 rounded px-1.5 py-0.5 text-left transition-colors hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
      >
        <span
          data-role="text"
          class={["min-w-0 whitespace-pre-wrap", @value == "" && "text-ink-muted"]}
        >
          {(@value == "" && "—") || @value}
        </span>
        <.icon
          name="edit"
          class="mt-0.5 size-3.5 shrink-0 text-ink-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
        />
      </button>

      <div
        :if={@editable? and @editing}
        phx-window-keydown={@cancel_event}
        phx-key="Escape"
      >
        <textarea
          id={"#{@id}-input"}
          data-role="input"
          name={@field}
          rows={@rows}
          aria-label={@label}
          aria-describedby={@status && "#{@id}-status"}
          aria-invalid={match?({:error, _}, @status) && "true"}
          phx-mounted={@autofocus && Phoenix.LiveView.JS.focus()}
          class={[
            "w-full min-w-0 rounded-md border border-brand-strong bg-surface px-1.5 py-1 text-sm text-ink focus:outline-none focus:ring-1 focus:ring-brand-strong/30",
            @input_class
          ]}
        >{@value}</textarea>
      </div>

      <span :if={not @editable?} class={["whitespace-pre-wrap", @value == "" && "text-ink-muted"]}>
        {(@value == "" && "—") || @value}
      </span>

      <span data-role="saving" class="mt-0.5 hidden flex items-center gap-1 text-xs text-ink-muted">
        <.icon name="refresh" class="size-3 motion-safe:animate-spin" /> Saving…
      </span>

      <.commit_status id={"#{@id}-status"} status={@status} />
    </div>
    """
  end

  @doc """
  Renders the outcome of one commit beside the fact that made it.

  This is the single voice every in-place write reports in, whether the fact
  is an `<.inline_edit>`, a choice that commits on change, or a group of
  interdependent facts with one Apply:

    * `nil` — nothing to report;
    * `:saved` — the last commit was stored, announced as a `role="status"`;
    * `{:error, message}` — the last commit was refused, announced as a
      `role="alert"`, with `message` naming the rejected value and why.

  `Bilimbi.Base.UI.CommitStatus` records these outcomes and owns the rules
  around them; the owner passes what it recorded as `status`.

  ## Examples

      <.commit_status id="address-location-status" status={@field_status["location"]} />
  """
  attr(:id, :string, required: true)

  attr(:status, :any,
    required: true,
    doc: "the outcome of the last commit: `nil`, `:saved`, or `{:error, message}`"
  )

  def commit_status(assigns) do
    assigns = assign(assigns, :status, normalize_commit_status(assigns.status))

    ~H"""
    <p
      :if={@status == :saved}
      id={@id}
      role="status"
      class="mt-0.5 flex items-center gap-1 text-xs text-success-ink"
    >
      <.icon name="success" class="size-3" /> Saved
    </p>

    <p
      :for={{:error, message} <- List.wrap(@status)}
      id={@id}
      role="alert"
      class="mt-0.5 flex items-start gap-1 text-xs text-danger-ink"
    >
      <.icon name="error" class="mt-0.5 size-3 shrink-0" />
      <span class="min-w-0 [overflow-wrap:anywhere]">{message}</span>
    </p>
    """
  end

  # `Bilimbi.Base.UI.CommitStatus` owns the vocabulary and the bookkeeping
  # behind it; the components only render what it recorded.
  defp normalize_commit_status(status), do: Bilimbi.Base.UI.CommitStatus.normalize(status)

  @doc """
  Renders the demoted "← Back" navigation of a page header.

  Returning to where the operator came from is a secondary action, so it is a
  plain link, never a button: the header's buttons are for the work the page
  is about. The visible text is always "← Back"; `title` names the
  destination for the tooltip and assistive technology when the page has more
  than one way back (for example "Back to company" beside "Back to list").

  ## Examples

      <.back_link id="address-back-list" navigate={~p"/addresses"} />
      <.back_link id="address-back-company" navigate={~p"/companies/1"} title="Back to company" />
  """
  attr(:id, :string, default: nil)
  attr(:navigate, :string, required: true)

  attr(:title, :string,
    default: nil,
    doc:
      "names the destination; it must start with \"Back\" so the label contains the visible text"
  )

  attr(:class, :any, default: nil)

  def back_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      title={@title}
      aria-label={@title}
      class={[demoted_action_class(), @class]}
    >
      <span aria-hidden="true">←</span> Back
    </.link>
    """
  end

  @doc """
  Renders a demoted secondary action as a plain link.

  A page's buttons are for the work the page is about. An action that only
  takes the operator to a related workflow — "Manage" on the Departments
  section of a company, the list of types beside the list that uses them — is
  a link in `text-link`, never a button. It sits on the section it belongs to,
  or beside the page's primary action when the whole list is what it relates
  to, as the type lists of `/companies` and `/employees` do, and its leading
  glyph is named through the icon registry so the link keeps the icon
  Belimbing uses for the same action. `<.back_link>` is the fixed-text member
  of the same family.

  A quiet action that Belimbing presents the same way but that submits a
  request rather than navigating — Impersonate on `/users/:id`, a `POST` —
  passes `href` and `method` in place of `navigate`; the treatment is the
  same, so the header reads as one labelled row (History, Impersonate,
  Back) whose only button is History's disclosure.

  The surface is closed: `id`, `icon` and `title` are required, exactly one
  of `navigate` or `href` names the destination, and there is nothing else,
  so every demoted action is addressable, reachable, glyphed and named, and
  none can style itself away from the one treatment the family shares.

  ## Examples

      <.action_link
        id="company-departments-manage"
        icon="manage"
        navigate={~p"/companies/1/departments"}
        title="Manage departments"
      >
        Manage
      </.action_link>

      <.action_link
        id="user-impersonate"
        icon="bilimbi-impersonate"
        href={~p"/admin/impersonate/1"}
        method="post"
        title="Impersonate this user"
      >
        Impersonate
      </.action_link>
  """
  attr(:id, :string, required: true)
  attr(:navigate, :string, default: nil)

  attr(:href, :string,
    default: nil,
    doc: "the request destination of an action that submits rather than navigates"
  )

  attr(:method, :string,
    default: nil,
    doc: "the HTTP method sent to `href`; ignored with `navigate`"
  )

  attr(:icon, :string,
    required: true,
    doc: "a registry action name rendered before the text"
  )

  attr(:title, :string,
    required: true,
    doc:
      "names the destination; it must contain the visible text so the label does not replace it"
  )

  slot(:inner_block, required: true)

  def action_link(%{navigate: navigate, href: href} = assigns)
      when (is_binary(navigate) and is_nil(href)) or (is_nil(navigate) and is_binary(href)) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      href={@href}
      method={@href && @method}
      title={@title}
      aria-label={@title}
      class={demoted_action_class()}
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def action_link(assigns) do
    raise ArgumentError,
          "action_link #{inspect(assigns.id)} needs exactly one of navigate or href, got " <>
            "navigate: #{inspect(assigns.navigate)}, href: #{inspect(assigns.href)}"
  end

  @doc """
  The one treatment for a demoted secondary action: a quiet labelled control
  in `text-link` that darkens on hover.

  `<.back_link>` and `<.action_link>` are the link members of the family and
  apply it themselves. It is public for the one member that is structurally
  not a link: the `record.history` trigger is a disclosure button. It takes
  this class so History sits in the header row as the same kind of thing as
  Impersonate and Back, as Belimbing's `admin/*/show` pages present it.
  The button discloses; it does not change data. Do not use this class to
  style a control that changes data — that control is a `<.button>`.
  """
  @spec demoted_action_class() :: String.t()
  def demoted_action_class do
    "inline-flex items-center gap-1 whitespace-nowrap text-sm text-link transition-colors hover:text-ink focus-visible:outline-none focus-visible:rounded-sm focus-visible:ring-1 focus-visible:ring-brand-strong/40"
  end

  @doc """
  Renders the heading row of one section on a detail page.

  A detail page is a stack of sections, each a `<.card>` whose body opens
  with this row and then holds the section's facts (`<.list>`), its table or
  its form. The row is the one heading treatment those sections share, so a
  page never hand-writes a section title: the small-caps title Belimbing's
  `admin/*/show` cards use, an optional count badge beside it, an optional
  description line under it, and two action slots that mirror `<.header>`:
  `title_actions` sits right beside the title (a demoted edit icon that opens
  a grouped editor) and `actions` sits at the end of the row (a "Manage"
  action link, the section's own buttons).

  The title is an `<h2>`: a section is a direct child of the page, whose
  title is the `<h1>`. Pass `id` to name the heading when the section's
  landmark carries `aria-labelledby`.

  ## Examples

      <.section_heading id="company-details-heading" title="Company Details" />

      <.section_heading id="departments-heading" title="Departments" count={length(@departments)}>
        <:actions>
          <.action_link id="departments-manage" icon="manage" navigate={~p"/..."}>Manage</.action_link>
        </:actions>
      </.section_heading>

      <.section_heading title="Geographic Location">
        <:title_actions><.icon_button icon="edit" label="Edit location" context={:inline} /></:title_actions>
        <:description>Country, division, postcode and locality are applied together.</:description>
      </.section_heading>
  """
  attr(:id, :string, default: nil, doc: "DOM id of the `<h2>`")
  attr(:title, :string, required: true)
  attr(:count, :integer, default: nil, doc: "how many records the section lists, as a badge")
  attr(:class, :any, default: nil)
  slot(:title_actions, doc: "controls that sit right beside the title")
  slot(:description, doc: "one line under the title saying what the section holds")
  slot(:actions, doc: "controls at the end of the heading row")

  def section_heading(assigns) do
    ~H"""
    <div class={["mb-4 flex items-start justify-between gap-3", @class]}>
      <div class="min-w-0">
        <div class="flex items-center gap-2">
          <h2 id={@id} class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
            {@title}
          </h2>
          <.badge :if={@count}>{@count}</.badge>
          {render_slot(@title_actions)}
        </div>
        <div :if={@description != []} class="mt-0.5 text-xs text-ink-subtle">
          {render_slot(@description)}
        </div>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders the controls of one workspace tile, floating over the tile's top
  right corner: a grip and a menu. A tile has no title bar. The page's own
  heading is the title, and a bar that repeated it cost every tile a row.

  The caller's tile element is `relative` and carries the `group` class.
  The grip and the menu trigger stay out of sight until the pointer is over
  the tile, focus is inside these controls, or the tile is focused, so an
  unfocused tile shows only its page. `app.css` pads the framed page
  header, marked `data-page-header` by `header/1`, so the controls never
  cover a page's own action.

  The menu offers the two operations a pointer needs, flipping the split
  and closing the tile. Everything else the workspace can do to a tile
  (fill the workspace, swap, move, follow, make master, open alone) is a
  key in the `Ctrl+.` tiling mode, listed in the key table of
  `apps/base/tiling/docs/README.md`; do not grow this menu back into a second
  list of them. It is a disclosure: its trigger's `aria-expanded` is the one record of
  open, the list derives its visibility from it, and the `DisclosureDismiss`
  hook closes it when focus leaves or Escape is pressed, exactly as
  `<.multi_select>` does. Either entry runs the caller's command and closes
  the menu; the flip hands focus back to the trigger, since the tile is
  still there to act on. `title` names the trigger for assistive
  technology, because nothing else on the tile's chrome says which page it
  belongs to.

  The grip is the handle for dragging the tile onto another to swap them.
  The host's hook reads `data-tile-grip`; it is a pointer affordance only
  and takes no focus, because the mode's `s` and `H J K L` are the
  pointer-free way.

  Two states stay visible whether or not the tile is focused: the link icon
  of a tile that follows selections (`Bilimbi.Base.UI.Workspace`), and the
  "Master" mark of the master tile in master mode, where the menu names the
  layout-wide orientation control accordingly.

  ## Examples

      <.tile_controls
        id="tile-t1-controls"
        title="Companies"
        focused
        on_split={JS.push("toggle-split", value: %{id: "t1"})}
        on_close={JS.push("close-tile", value: %{id: "t1"})}
      />
  """
  attr(:id, :string, required: true)

  attr(:title, :string,
    required: true,
    doc: "the page's own title, read from its document; names the menu"
  )

  attr(:focused, :boolean, default: false, doc: "a focused tile keeps its controls in sight")
  attr(:on_split, JS, required: true, doc: "flips the split holding this tile")
  attr(:on_close, JS, required: true)
  attr(:master_layout, :boolean, default: false)
  attr(:master_tile, :boolean, default: false)

  attr(:following, :boolean,
    default: false,
    doc: "whether this tile opens the records other tiles select"
  )

  def tile_controls(assigns) do
    menu = "#{assigns.id}-menu"
    dismiss = JS.set_attribute({"aria-expanded", "false"}, to: "##{menu}")

    assigns =
      assigns
      |> assign(:menu, menu)
      |> assign(:dismiss, dismiss)
      |> assign(:escape, JS.focus(dismiss, to: "##{menu}"))
      |> assign(:toggle, JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{menu}"))
      |> assign(
        :entry_class,
        "block w-full rounded-sm px-2 py-1 text-left text-xs focus-visible:outline-none"
      )

    ~H"""
    <div
      id={@id}
      phx-hook="DisclosureDismiss"
      data-dismiss={@dismiss}
      data-escape={@escape}
      phx-click-away={@dismiss}
      data-tile-controls
      class="absolute right-1 top-1 z-20 flex flex-col items-end gap-0.5 text-xs"
    >
      <%!-- One group, so the grip and the trigger appear together. It stays
      in sight while the menu is open, wherever the pointer is. --%>
      <div class={[
        "relative flex items-center rounded-md border border-line bg-surface shadow-xs transition-opacity",
        "group-hover:opacity-100 focus-within:opacity-100 has-[[aria-expanded=true]]:opacity-100",
        !@focused && "opacity-0"
      ]}>
        <span
          id={"#{@id}-grip"}
          data-tile-grip
          title={gettext("Drag onto another tile to swap")}
          class="grid size-5 cursor-grab touch-none place-items-center rounded-sm text-ink-muted hover:bg-surface-sunken hover:text-ink active:cursor-grabbing"
        >
          <.icon name="hero-bars-2" class="size-3.5" />
        </span>
        <button
          id={@menu}
          type="button"
          aria-expanded="false"
          aria-controls={"#{@menu}-items"}
          aria-label={gettext("Tile menu: %{title}", title: @title)}
          title={gettext("Tile menu")}
          data-tile-menu
          phx-click={@toggle}
          class="peer grid size-5 shrink-0 place-items-center rounded-sm text-ink-muted transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40"
        >
          <.icon name="hero-ellipsis-horizontal" class="size-3.5" />
        </button>
        <div
          id={"#{@menu}-items"}
          data-tile-menu
          class="hidden peer-aria-expanded:block absolute right-0 top-full z-30 mt-0.5 min-w-40 rounded-md border border-line bg-surface p-1 shadow-lg"
        >
          <button
            type="button"
            id={"#{@id}-split"}
            phx-click={dismiss_after(@on_split, @escape)}
            class={[
              @entry_class,
              "text-ink hover:bg-surface-muted focus-visible:bg-surface-muted"
            ]}
          >
            {if @master_layout,
              do: gettext("Flip master direction"),
              else: gettext("Flip split direction")}
          </button>
          <button
            type="button"
            id={"#{@id}-close"}
            phx-click={dismiss_after(@on_close, @dismiss)}
            class={[
              @entry_class,
              "text-danger hover:bg-danger-surface hover:text-danger-ink focus-visible:bg-danger-surface focus-visible:text-danger-ink"
            ]}
          >
            {gettext("Close tile")}
          </button>
        </div>
      </div>
      <%!-- Under the buttons, inside the corner a page header leaves free. --%>
      <div :if={@master_tile or @following} class="flex items-center gap-0.5">
        <span
          :if={@following}
          id={"#{@id}-following"}
          title={gettext("Follows selections")}
          class="grid size-4 place-items-center rounded-sm bg-surface text-brand-strong"
        >
          <.icon name="hero-link" class="size-3" />
          <span class="sr-only">{gettext("Follows selections")}</span>
        </span>
        <span
          :if={@master_tile}
          id={"#{@id}-master"}
          class="rounded-sm bg-surface px-1 text-[10px] leading-4 text-ink-muted"
        >
          {gettext("Master")}
        </span>
      </div>
    </div>
    """
  end

  # Runs the caller's command, then closes the menu; both are one click.
  defp dismiss_after(%JS{ops: ops}, %JS{ops: close}), do: %JS{ops: ops ++ close}

  @doc """
  Renders the divider between two workspace tiles, positioned by the caller.

  It is a focusable `role="separator"` with the orientation of the line it
  draws: a side-by-side split draws a vertical line. The host's hook resizes
  by dragging it with the mouse, and by the arrow keys while it has focus,
  so every divider is reachable without a pointer. It carries no colour at
  rest; the gap between tiles is the canvas, as in Hyprland, and the divider
  surfaces on hover and focus.

  Its position arrives as `data-place`, applied by the host's hook through
  the CSSOM: the Content-Security-Policy allows no `style` attribute, so a
  `style` here would be ignored by the browser and the handle would sit at
  the origin.

  ## Examples

      <.split_handle
        id="split-s3"
        direction={:h}
        label="Resize Companies and Users"
        data-place="left: 50%; top: 0%; height: 100%"
        data-split="s3"
      />
  """
  attr(:id, :string, required: true)

  attr(:direction, :atom,
    required: true,
    values: [:h, :v],
    doc: "`:h` side by side, `:v` top and bottom"
  )

  attr(:label, :string, required: true, doc: "names the two tiles the divider separates")
  attr(:class, :any, default: nil, doc: "a placement by utility class, where no hook places it")

  attr(:rest, :global,
    doc: "`data-split` carries the split id and `data-place` the position for the host's hook"
  )

  def split_handle(assigns) do
    ~H"""
    <div
      id={@id}
      role="separator"
      tabindex="0"
      aria-orientation={if @direction == :h, do: "vertical", else: "horizontal"}
      aria-label={@label}
      data-direction={@direction}
      class={[
        "absolute z-10 select-none rounded-sm transition-colors hover:bg-surface-sunken focus-visible:bg-brand-surface focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong",
        @direction == :h && "w-1.5 -translate-x-1/2 cursor-col-resize",
        @direction == :v && "h-1.5 -translate-y-1/2 cursor-row-resize",
        @class
      ]}
      {@rest}
    >
    </div>
    """
  end
end
