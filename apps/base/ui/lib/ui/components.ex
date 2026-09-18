defmodule Bilimbi.Base.UI.Components do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS. Bilimbi owns its component
  design directly rather than delegating product appearance to a component
  theme. Every component here styles itself with the semantic color roles
  declared in `assets/css/app.css` — `surface`, `ink`, `line`, `action`,
  `brand`, `success`, `warning`, and `danger`. A raw palette class such as
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

  alias Bilimbi.Base.UI.IconRegistry
  alias Phoenix.LiveView.JS

  @doc """
  Renders one flash message.

  The message is the flash entry for `kind`, or the inner block. Every
  severity is `role="alert"`; announcing success and info politely instead
  is deliberate follow-up work, not part of this contract.
  `:success` and `:info` share the success colouring and differ by icon: most
  `put_flash(:info, ...)` call sites report a completed write, so the two
  cannot be told apart by colour until those callers move to `:success`.

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
      role="alert"
      class="w-full"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-2xl border p-4 text-sm shadow-xl shadow-ink/[0.08] backdrop-blur",
        @kind in [:success, :info] &&
          "border-success-line bg-success-surface/95 text-success-ink",
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
  """
  attr(:id, :string, required: true)

  def connection_banners(assigns) do
    assigns =
      assigns
      |> assign(:client_id, "#{assigns.id}-client-error")
      |> assign(:server_id, "#{assigns.id}-server-error")

    ~H"""
    <.flash
      id={@client_id}
      kind={:error}
      title={gettext("Connection interrupted")}
      phx-disconnected={
        show(".phx-client-error ##{@client_id}")
        |> JS.remove_attribute("hidden", to: ".phx-client-error ##{@client_id}")
      }
      phx-connected={hide("##{@client_id}") |> JS.set_attribute({"hidden", ""})}
      hidden
    >
      {gettext("Reconnecting…")}
    </.flash>

    <.flash
      id={@server_id}
      kind={:error}
      title={gettext("Server unavailable")}
      phx-disconnected={
        show(".phx-server-error ##{@server_id}")
        |> JS.remove_attribute("hidden", to: ".phx-server-error ##{@server_id}")
      }
      phx-connected={hide("##{@server_id}") |> JS.set_attribute({"hidden", ""})}
      hidden
    >
      {gettext("Attempting to reconnect")}
      <.icon name="hero-arrow-path" class="ml-1 size-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders an inline status alert (Belimbing's `x-ui.alert` counterpart).

  Kinds map to the honest status roles: `:info`, `:success`, `:warning`,
  `:error`.

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
      role="alert"
      class={[
        "flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-sm",
        @kind == :info && "border-line bg-surface-sunken text-ink",
        @kind == :success && "border-success-line bg-success-surface text-success-ink",
        @kind == :warning && "border-warning-line bg-warning-surface text-warning-ink",
        @kind == :error && "border-danger-line bg-danger-surface text-danger-ink",
        @class
      ]}
      {@rest}
    >
      <.icon name={status_icon(@kind)} class="mt-0.5 size-4 shrink-0" />
      <div class="min-w-0">{render_slot(@inner_block)}</div>
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

  # A busy control is also disabled: the activation that made it busy is the
  # one whose outcome is pending, and a second one would duplicate the work.
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
      |> assign(:control_class, [
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
      ])
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

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. For two to five exclusive choices that should stay
  visible, use `radio_group/1` rather than a single input.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select multi_select tel text textarea time url week hidden)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")

  attr(:size, :integer,
    default: nil,
    doc: "visible rows for a `multiple` select; defaults to 5 so no row is half-painted"
  )

  attr(:class, :any, default: nil, doc: "the input class to use over defaults")
  attr(:error_class, :any, default: nil, doc: "the input error class to use over defaults")

  attr(:hint, :string,
    default: nil,
    doc: """
    helper text rendered inside the field wrapper, below the control.

    Placing it here rather than in a sibling `<p>` is the point: a paragraph
    after `<.input>` sits outside the wrapper that owns `mb-4`, so callers were
    compensating with four different spacings -- `mt-1`, `mt-1 mb-4`, `mt-0.5`
    and even `-mt-2 mb-4` (#279).
    """
  )

  attr(:wrapper_class, :any, default: nil, doc: "the class for the control wrapper")
  attr(:label_class, :any, default: nil, doc: "the class for the control label")

  attr(:rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)
  )

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # Without a field there is no id to hang a label off, so `for` would render
  # empty and the label would announce to nothing. Fall back to the input name.
  def input(%{id: nil, name: name} = assigns) when is_binary(name) do
    assigns |> assign(:id, name) |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <label for={@id} class={["flex items-center gap-2.5 text-sm text-ink", @label_class]}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={
            @class ||
              "size-4 shrink-0 rounded border-high-contrast-line accent-action focus:outline-none focus:ring-2 focus:ring-brand-strong/30"
          }
          {@rest}
        />{@label}
      </label>
      <p :if={@hint} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <label
        :if={@label}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={
          [
            field_class(@class, @error_class, @errors),
            # A listbox is sized in rows, not pixels. `py-2` makes the box taller
            # than the rows it holds, and the browser fills the slack with the
            # *next* option -- so the last row is painted sliced through its
            # glyphs and reads as a rendering fault rather than "scroll for more"
            # (#281). Height comes from `size` instead.
            @multiple && "!py-0"
          ]
        }
        multiple={@multiple}
        size={@multiple && (@size || 5)}
        {@rest}
      >
        <option :if={@prompt} value="" selected={@value in [nil, ""]}>{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <p :if={@hint} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "multi_select"} = assigns) do
    multi_select(assigns)
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <label
        :if={@label}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={field_class(@class, @error_class, @errors, "min-h-24")}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <p :if={@hint} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <label
        :if={@label}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={field_class(@class, @error_class, @errors)}
        {@rest}
      />
      <p :if={@hint} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # One control family for every field type. `class` replaces the default
  # entirely; `error_class` replaces only the invalid-state styling.
  defp field_class(class, error_class, errors, extra \\ nil) do
    [
      class || field_base_class(),
      is_nil(class) && extra,
      if errors == [] do
        "border-high-contrast-line"
      else
        error_class || "border-danger focus:border-danger focus:ring-danger/20"
      end
    ]
  end

  defp field_base_class(padding \\ "px-3") do
    "block w-full rounded-md border bg-surface #{padding} py-1.5 text-sm text-ink shadow-xs " <>
      "transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none " <>
      "focus:ring-2 focus:ring-brand-strong/30 disabled:cursor-not-allowed " <>
      "disabled:bg-surface-sunken disabled:text-ink-subtle"
  end

  @doc """
  Renders a multi-select dropdown component (Belimbing's `x-ui.multi-select` counterpart).

  Displays a button showing the selection summary (e.g. "All roles", "1 role selected",
  or "3 roles selected") with a chevron icon, and toggles a floating menu containing
  checkboxes for each option.

  ## Examples

      <.multi_select
        id="users-role-filter"
        field={@filters_form[:roleIds]}
        placeholder="All roles"
        selection_label=":count role selected|:count roles selected"
        options={@role_options}
      />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any, default: nil)
  attr(:label, :string, default: nil)
  attr(:label_class, :any, default: nil)
  attr(:wrapper_class, :any, default: nil)
  attr(:class, :any, default: nil)

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example @form[:role_ids]"
  )

  attr(:errors, :list, default: [])

  attr(:options, :list,
    default: [],
    doc: "the options to display, list of {label, value} tuples, maps, or strings"
  )

  attr(:value, :any, default: nil, doc: "the selected values (if not using field)")
  attr(:placeholder, :string, default: "All options", doc: "label when 0 items selected")

  attr(:selection_label, :string,
    default: ":count option selected|:count options selected",
    doc: "singular|plural template string for selection count"
  )

  attr(:hint, :string, default: nil)
  attr(:rest, :global, doc: "arbitrary HTML attributes for the button")

  def multi_select(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    name =
      assigns[:name] ||
        if(String.ends_with?(field.name, "[]"), do: field.name, else: field.name <> "[]")

    value = if(is_nil(assigns[:value]), do: field.value, else: assigns[:value])
    id = assigns[:id] || field.id

    assigns
    |> assign(field: nil, id: id, name: name, value: value)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> multi_select()
  end

  def multi_select(%{id: nil, name: name} = assigns) when is_binary(name) do
    assigns |> assign(:id, name) |> multi_select()
  end

  def multi_select(assigns) do
    input_name =
      case assigns[:name] do
        nil ->
          "#{assigns.id}[]"

        name when is_binary(name) ->
          if String.ends_with?(name, "[]"), do: name, else: name <> "[]"

        name ->
          to_string(name) <> "[]"
      end

    selected_values =
      assigns[:value]
      |> List.wrap()
      |> Enum.map(&to_string/1)

    normalized_options =
      Enum.map(assigns.options || [], fn
        {label, val} ->
          {to_string(label), to_string(val)}

        [label, val] ->
          {to_string(label), to_string(val)}

        %{label: label, value: val} ->
          {to_string(label), to_string(val)}

        val when is_binary(val) or is_atom(val) or is_integer(val) ->
          {to_string(val), to_string(val)}
      end)

    selected_count = Enum.count(normalized_options, fn {_, val} -> val in selected_values end)

    summary_label =
      format_selection_summary(
        selected_count,
        assigns.placeholder,
        assigns.selection_label
      )

    assigns =
      assigns
      |> assign(:input_name, input_name)
      |> assign(:selected_values, selected_values)
      |> assign(:normalized_options, normalized_options)
      |> assign(:selected_count, selected_count)
      |> assign(:summary_label, summary_label)

    ~H"""
    <div
      id={"#{@id}-wrapper"}
      class={["relative", @wrapper_class || "mb-4"]}
    >
      <input type="hidden" name={@input_name} value="" />
      <label
        :if={@label}
        id={"#{@id}-label"}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}
      </label>

      <button
        id={@id}
        type="button"
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls={"#{@id}-options"}
        phx-click={
          JS.toggle_class("hidden", to: "##{@id}-options")
          |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
        }
        class={[
          "flex w-full items-center justify-between gap-3 rounded-md border border-line bg-surface py-1.5 px-3 text-left text-sm text-ink shadow-xs transition hover:bg-surface-muted focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/30",
          @class
        ]}
        {@rest}
      >
        <span class="truncate font-normal">
          {@summary_label}
        </span>
        <span
          id={"#{@id}-chevron"}
          class="inline-flex shrink-0 transition-transform duration-200"
        >
          <.icon
            name="hero-chevron-down"
            class="size-4 text-ink-muted"
          />
        </span>
      </button>

      <div
        id={"#{@id}-options"}
        phx-click-away={
          JS.add_class("hidden", to: "##{@id}-options")
          |> JS.remove_class("rotate-180", to: "##{@id}-chevron")
        }
        class="hidden absolute left-0 z-30 mt-1 max-h-60 w-full min-w-56 overflow-y-auto rounded-xl border border-line bg-surface p-1.5 shadow-lg space-y-0.5"
      >
        <label
          :for={{opt_label, opt_value} <- @normalized_options}
          for={"#{@id}-option-#{opt_value}"}
          class="flex cursor-pointer items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-sm text-ink hover:bg-surface-sunken select-none transition"
        >
          <input
            type="checkbox"
            id={"#{@id}-option-#{opt_value}"}
            name={@input_name}
            value={opt_value}
            checked={opt_value in @selected_values}
            class="size-4 shrink-0 rounded border-line text-action accent-action focus:ring-2 focus:ring-brand-strong/30"
          />
          <span class="truncate font-normal">{opt_label}</span>
        </label>
        <div
          :if={@normalized_options == []}
          class="px-2.5 py-2 text-sm text-ink-muted"
        >
          {gettext("No options available.")}
        </div>
      </div>

      <p :if={@hint} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp format_selection_summary(0, placeholder, _selection_label),
    do: placeholder || "All options"

  defp format_selection_summary(count, _placeholder, selection_label) do
    template =
      case String.split(selection_label || ":count selected", "|") do
        [singular, _plural] when count == 1 -> singular
        [_singular, plural] -> plural
        [single] -> single
      end

    String.replace(template, ":count", Integer.to_string(count))
  end

  @doc """
  Renders a radio group for two to five exclusive choices that stay visible.

  A `Phoenix.HTML.FormField` may be passed to retrieve the name, id, and
  selected value. Otherwise pass `name`, `id`, and `value` explicitly.

  ## Examples

      <.radio_group
        field={@form[:appearance]}
        label="Appearance"
        options={[{"System", "system"}, {"Light", "light"}, {"Dark", "dark"}]}
      />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:appearance]"
  )

  attr(:errors, :list, default: [])

  attr(:options, :list,
    required: true,
    doc: "the options to display, list of {label, value} tuples, maps, or strings"
  )

  attr(:hint, :string, default: nil)
  attr(:disabled, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:wrapper_class, :any, default: nil)
  attr(:label_class, :any, default: nil)
  attr(:rest, :global)

  def radio_group(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> radio_group()
  end

  def radio_group(%{id: nil, name: name} = assigns) when is_binary(name) do
    assigns |> assign(:id, name) |> radio_group()
  end

  def radio_group(assigns) do
    assigns =
      assigns
      |> assign(:normalized_options, Enum.map(assigns.options, &normalize_choice/1))
      |> assign(:selected, radio_value(assigns[:value]))

    ~H"""
    <fieldset
      id={@id}
      disabled={@disabled}
      class={@wrapper_class || "mb-4"}
      {@rest}
    >
      <legend :if={@label} class={["mb-1.5 text-sm font-medium text-ink", @label_class]}>
        {@label}
      </legend>
      <div class="space-y-2">
        <label
          :for={{opt_label, opt_value} <- @normalized_options}
          for={"#{@id}-#{opt_value}"}
          class={[
            "flex items-center gap-2 text-sm text-ink",
            @disabled && "cursor-not-allowed opacity-50",
            !@disabled && "cursor-pointer"
          ]}
        >
          <input
            type="radio"
            id={"#{@id}-#{opt_value}"}
            name={@name}
            value={opt_value}
            checked={opt_value == @selected}
            disabled={@disabled}
            class={
              @class ||
                "size-4 shrink-0 accent-action focus:outline-none focus:ring-2 focus:ring-brand-strong/30 disabled:cursor-not-allowed"
            }
          />
          {opt_label}
        </label>
      </div>
      <p :if={@hint} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  defp normalize_choice({label, value}), do: {to_string(label), to_string(value)}
  defp normalize_choice([label, value]), do: {to_string(label), to_string(value)}
  defp normalize_choice(%{label: label, value: value}), do: {to_string(label), to_string(value)}

  defp normalize_choice(value) when is_binary(value) or is_atom(value) or is_integer(value),
    do: {to_string(value), to_string(value)}

  defp radio_value(nil), do: nil
  defp radio_value(value), do: to_string(value)

  @doc """
  Renders pagination controls matching Belimbing design parity.

  Follows Belimbing's pagination contract with single-page optimization:
  the summary count is rendered whenever there are results (`total_pages > 0`),
  the rows-per-page selector is always available, and the page navigation
  controls (previous, numbers, next) are rendered only when there are multiple
  pages (`total_pages > 1`).
  """
  attr(:id, :string, required: true)
  attr(:page, :any, required: true)
  attr(:page_sizes, :list, default: [25, 50, 100, 300])
  attr(:filters_form, :any, required: true)
  attr(:filters_event, :string, default: "filters")
  attr(:page_event, :string, default: "page")

  def pagination(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Pagination"
      class="flex flex-col gap-2 border-t border-low-contrast-line px-2 py-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <p :if={@page.total_pages > 0} id={"#{@id}-summary"} class="text-xs text-ink-muted">
          {page_summary(@page)}
        </p>
        <.form
          id={"#{@id}-page-size-form"}
          for={@filters_form}
          phx-change={@filters_event}
          class="flex items-center gap-1.5"
        >
          <span class="text-xs text-ink-muted">{gettext("Rows per page")}</span>
          <.input
            id={"#{@id}-page-size"}
            type="select"
            field={@filters_form[:perPage]}
            label="Rows per page"
            label_class="sr-only"
            wrapper_class="mb-0"
            options={page_size_options(@page_sizes)}
            class="h-7 w-auto rounded-md border border-line bg-surface py-0 pl-2 pr-6 text-xs tabular-nums text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30"
          />
        </.form>
      </div>
      <div
        :if={@page.total_pages > 1}
        class="flex items-center gap-1"
        role="list"
        aria-label="Page navigation"
      >
        <button
          id={"#{@id}-previous"}
          type="button"
          phx-click={@page_event}
          phx-value-page={@page.page - 1}
          disabled={@page.page <= 1}
          aria-label="Previous page"
          title="Previous page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <.icon name="page-previous" class="size-3.5" />
        </button>
        <%= for step <- pagination_steps(@page) do %>
          <span :if={step == :ellipsis} class="px-1 text-xs text-ink-subtle" aria-hidden="true">…</span>
          <button
            :if={is_integer(step)}
            id={"#{@id}-page-#{step}"}
            type="button"
            phx-click={@page_event}
            phx-value-page={step}
            aria-current={if(step == @page.page, do: "page")}
            aria-label={"Page #{step}"}
            class={[
              "grid size-7 place-items-center rounded-md border text-xs tabular-nums transition focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
              step == @page.page && "border-selection-line bg-brand-surface text-brand-ink",
              step != @page.page && "border-line bg-surface text-ink hover:bg-surface-sunken"
            ]}
          >
            {step}
          </button>
        <% end %>
        <button
          id={"#{@id}-next"}
          type="button"
          phx-click={@page_event}
          phx-value-page={@page.page + 1}
          disabled={@page.page >= @page.total_pages or @page.total_pages == 0}
          aria-label="Next page"
          title="Next page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <.icon name="page-next" class="size-3.5" />
        </button>
      </div>
    </nav>
    """
  end

  @doc """
  Renders the shared list filter toolbar: search fields, selects, and date
  inputs framed as one open toolbar above the list surface (Design Spec C04).

  Controls are declared through one repeating `control` slot and render in the
  order they are written, so the template reads the way the toolbar looks.

  Filter state itself stays where it already lives — the caller's form, event,
  and URL round-trip are untouched, so the same inputs return the same rows.
  This component owns only composition and presentation:

    * Every control's framing comes from one shared field rule. The toolbar
      takes no per-control class, because a per-control class is how five
      controls end up laid out by two rules with nothing declaring which is
      correct.
    * Every search box carries the same leading magnifier, the same room that
      clears it, and the same debounce, length cap, and autocomplete answer.
      None of them is a caller's choice, so an operator who learns one list
      recognises the search box on the next.
    * Enter filters in place on every toolbar. The form carries the caller's
      event as both `phx-change` and `phx-submit`, because a form with only a
      change binding falls back to a native submit that reloads the page with
      the form's own param names and drops the filter the operator typed.
    * Labels are always screen-reader only. A page that shows some and hides
      others drops the labelled controls below their row-mates, because a
      visible label adds a row of height only some cells carry.
    * Helper text sits below its control in one shape. A select's and a date's
      rides its own `input`; a search box's sits below the box the magnifier
      is centred in, so helper text never stretches that box and drags the
      magnifier off the input.
    * Cells wrap instead of squeezing. Each control is its own flex item, so
      native date inputs stack on a narrow viewport rather than holding a
      grid row wider than the page.

  ## Examples

      <.filter_toolbar id="companies-filters" form={@filters_form} event="filters">
        <:control
          type={:search}
          field={@filters_form[:search]}
          id="companies-search"
          label="Search companies"
          placeholder="Search by name, code, legal name, email, or jurisdiction..."
        />
        <:control
          type={:select}
          field={@filters_form[:status_filter]}
          id="companies-status-filter"
          label="Status filter"
          options={[{"All statuses", "all"}, {"Active", "active"}]}
        />
      </.filter_toolbar>
  """
  attr(:id, :string, required: true, doc: "the toolbar form's DOM id")

  attr(:form, :any,
    required: true,
    doc: "the caller's Phoenix form; field names and params are unchanged"
  )

  attr(:event, :string,
    required: true,
    doc: "the event the caller already handles; bound to both phx-change and phx-submit"
  )

  attr(:class, :any,
    default: nil,
    doc:
      "extra classes for page context (for example mt-4 below tabs); the open-toolbar framing stays owned here"
  )

  slot :control, doc: "one filter control per entry, rendered in the order declared" do
    attr(:type, :atom,
      values: [:search, :select, :date],
      required: true,
      doc: "which control to render"
    )

    attr(:field, :any, required: true, doc: "the control's form field")
    attr(:id, :string, required: true, doc: "the control's DOM id")
    attr(:label, :string, required: true, doc: "the control's screen-reader-only label")

    attr(:options, :list,
      doc: "`:select` options passed to `Phoenix.HTML.Form.options_for_select/2`"
    )

    attr(:placeholder, :string, doc: "`:search` prompt text")
    attr(:hint, :string, doc: "helper text rendered below the control")
  end

  def filter_toolbar(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-change={@event}
      phx-submit={@event}
      class={["mb-2 flex flex-wrap items-start gap-x-3 gap-y-2", @class]}
    >
      <.toolbar_control :for={control <- @control} control={control} />
    </.form>
    """
  end

  attr(:control, :map, required: true)

  defp toolbar_control(%{control: %{type: :search}} = assigns) do
    ~H"""
    <div class="min-w-52 flex-1 basis-64">
      <.toolbar_label id={@control[:id]} label={@control[:label]} />
      <div class="relative">
        <.icon
          name="search"
          class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
        />
        <.input
          field={@control[:field]}
          id={@control[:id]}
          type="search"
          wrapper_class="mb-0"
          placeholder={@control[:placeholder]}
          phx-debounce="300"
          maxlength="255"
          autocomplete="off"
          class={field_base_class("pl-8 pr-3")}
        />
      </div>
      <p :if={@control[:hint]} class="mt-1.5 text-xs text-ink-subtle">{@control[:hint]}</p>
    </div>
    """
  end

  defp toolbar_control(%{control: %{type: :select}} = assigns) do
    ~H"""
    <div class="w-full min-w-0 sm:w-auto sm:min-w-36">
      <.toolbar_label id={@control[:id]} label={@control[:label]} />
      <.input
        field={@control[:field]}
        id={@control[:id]}
        type="select"
        wrapper_class="mb-0"
        options={@control[:options]}
        hint={@control[:hint]}
      />
    </div>
    """
  end

  defp toolbar_control(%{control: %{type: :date}} = assigns) do
    ~H"""
    <div class="w-full min-w-0 sm:w-auto">
      <.toolbar_label id={@control[:id]} label={@control[:label]} />
      <.input
        field={@control[:field]}
        id={@control[:id]}
        type="date"
        wrapper_class="mb-0"
        hint={@control[:hint]}
      />
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)

  defp toolbar_label(assigns) do
    ~H"""
    <label for={@id} class="sr-only">{@label}</label>
    """
  end

  defp page_summary(%{total_entries: 0}), do: "No results"

  defp page_summary(%{page: page, page_size: page_size, total_entries: total_entries}) do
    first = (page - 1) * page_size + 1
    last = min(page * page_size, total_entries)
    "Showing #{first} to #{last} of #{total_entries} results"
  end

  defp page_size_options(page_sizes), do: Enum.map(page_sizes, &{"#{&1}", &1})

  defp pagination_steps(%{total_pages: 0}), do: []

  defp pagination_steps(%{total_pages: total_pages}) when total_pages <= 5 do
    Enum.to_list(1..total_pages)
  end

  defp pagination_steps(%{page: page, total_pages: total_pages}) do
    [1, 2, page - 1, page, page + 1, total_pages]
    |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
    |> Enum.uniq()
    |> Enum.sort()
    |> insert_page_gaps()
  end

  defp insert_page_gaps(pages) do
    Enum.reduce(pages, [], fn
      page, [] ->
        [page]

      page, steps ->
        if page > List.last(steps) + 1, do: steps ++ [:ellipsis, page], else: steps ++ [page]
    end)
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
  """
  attr(:id, :string, required: true)
  attr(:value, :any, default: nil)
  attr(:format, :atom, values: [:date, :time, :datetime], default: :datetime)
  attr(:class, :any, default: nil)

  attr(:display, :any,
    default: nil,
    doc: "explicit display context that pins the instant to it; defaults to the process context"
  )

  def datetime(assigns) do
    display = assigns.display || Bilimbi.Base.UI.DateTimeDisplay.get()
    date_time = datetime_value(assigns.value)
    mode = display_mode(display)

    assigns =
      assigns
      |> assign(:date_time, date_time)
      |> assign(:date, date_value(assigns.value))
      |> assign(:mode, mode)
      # Both server-decidable modes are rendered up front, whatever the
      # current mode is, so the browser can follow a mode change by copying a
      # server string instead of formatting one of its own.
      |> assign(
        :text_company,
        date_time && policy_datetime(date_time, assigns.format, :company, display)
      )
      |> assign(:text_utc, date_time && server_datetime(date_time, assigns.format))
      |> assign(:text, date_time && policy_datetime(date_time, assigns.format, mode, display))

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

  defp policy_datetime(value, format, :local, _display), do: server_datetime(value, format)

  defp policy_datetime(value, format, :utc, _display), do: server_datetime(value, format)

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

  defp server_datetime(value, :date), do: Calendar.strftime(value, "%d/%m/%Y UTC")
  defp server_datetime(value, :time), do: Calendar.strftime(value, "%H:%M UTC")
  defp server_datetime(value, :datetime), do: Calendar.strftime(value, "%d/%m/%Y, %H:%M UTC")

  defp zoned_datetime(value, :date), do: Calendar.strftime(value, "%d/%m/%Y ") <> value.zone_abbr
  defp zoned_datetime(value, :time), do: Calendar.strftime(value, "%H:%M ") <> value.zone_abbr

  defp zoned_datetime(value, :datetime),
    do: Calendar.strftime(value, "%d/%m/%Y, %H:%M ") <> value.zone_abbr

  # Helper used by inputs to generate form errors
  slot(:inner_block, required: true)

  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-sm text-danger-ink">
      <.icon name="error" class="size-4 shrink-0 text-danger" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a card container with subtle border and rounded corners (Belimbing's `x-ui.card` counterpart).
  """
  attr(:id, :string, default: nil)
  attr(:title, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:inner_class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def card(assigns) do
    ~H"""
    <div
      id={@id}
      class={["rounded-xl border border-line bg-surface shadow-xs", @class]}
      {@rest}
    >
      <div :if={@title} class="border-b border-line px-4 py-3">
        <h3 class="text-base font-semibold text-ink">{@title}</h3>
      </div>
      <div class={["p-2", @inner_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
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
    values: [:narrow, :wide],
    default: :narrow,
    doc: "`:narrow` for a single-column form, `:wide` for a two-column one"
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
  Renders the page content container at the width of its workflow kind.

  Every screen is one of three kinds, and the width is chosen here and
  nowhere else (#287). Variation between same-kind screens has no
  user-visible reason, which is what DESIGN.md's *Stay consistent* forbids.

    * `:list` — operational index screens with tables and filters, at
      `max-w-7xl`. The densest tables (seven columns) need the room; a
      sparse table's trailing whitespace is benign, while a cramped dense
      table forces the navigation *Compact layout* asks us to avoid.
    * `:form` — single-column edit forms, at `max-w-2xl`.
    * `:detail` — show screens and the dashboard, at `max-w-4xl`.

  ## Examples

      <.page id="users-index">
        ...
      </.page>

      <.page variant={:form}>
        ...
      </.page>
  """
  attr(:id, :string, default: nil)
  attr(:variant, :atom, default: :list, values: [:list, :form, :detail])
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <div id={@id} class={["mx-auto", page_width(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp page_width(:list), do: "max-w-7xl"
  defp page_width(:form), do: "max-w-2xl"
  defp page_width(:detail), do: "max-w-4xl"

  @doc """
  Renders a header with title.
  """
  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:title_actions)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-start justify-between gap-6", "pb-4"]}>
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
      <div :if={@actions != []} class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a compact tab strip for sibling views of the same page.

  The selected tab uses the lime `brand-strong` underline. Unselected tabs stay
  muted and darken on hover.

  A tab that carries `href` or `patch` renders as a link; one that carries
  `click` renders as a button so in-page switching still works.

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
    <nav id={@id} class={["flex gap-1 border-b border-line", @class]} {@rest}>
      <.tab_item :for={tab <- @tab} tab={tab} />
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
      class={@tab_class}
      aria-current={@tab[:current] && "page"}
    >
      {render_slot(@tab)}
    </.link>
    <button
      :if={not @linked?}
      type="button"
      id={@tab[:id]}
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
      "-mb-px border-b-2 px-3 py-2 text-sm transition",
      "focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
      current? && "border-brand-strong font-medium text-ink-strong",
      not current? && "border-transparent text-ink-muted hover:text-ink"
    ]
  end

  @doc """
  Renders a table with compact Belimbing-parity styling.

  Pass `sort` on a column to render a header button that pushes `"sort"`
  with `phx-value-sort`. The active column gets `aria-sort`. Density is
  `px-2 py-1.5` for headers and `px-2 py-0.5` for row cells.

  `align={:right}` on a column right-aligns the header and cells (numeric
  columns). `caption` renders an `sr-only` `<caption>` so the grid has an
  accessible name.

  ## Examples

      <.table id="users" rows={@users} sort_by={@sort_by} sort_dir={@sort_dir} caption="Users">
        <:col :let={user} label="Name" sort="name" sort_id="users-sort-name">
          {user.name}
        </:col>
        <:col :let={user} label="Count" sort="count" align={:right}>{user.count}</:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :any, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  attr(:sort_by, :any, default: nil, doc: "active sort key; compared to each column's `sort`")
  attr(:sort_dir, :any, default: nil, doc: "`\"asc\"`/`\"desc\"` or `:asc`/`:desc`")

  attr(:sort_event, :string,
    default: "sort",
    doc: "the event name pushed when a column sort button is clicked"
  )

  attr(:framed, :boolean,
    default: true,
    doc: "when false, omit the outer card chrome so the table can sit in an existing panel"
  )

  attr(:caption, :string,
    default: nil,
    doc: "sr-only caption that names the table for assistive tech"
  )

  slot :col, required: true do
    attr(:label, :string)
    attr(:sort, :string, doc: "sort key pushed as phx-value-sort")
    attr(:sort_id, :string, doc: "DOM id for the sort button")
    attr(:align, :atom, values: [:right], doc: "right-align header and cells (numeric columns)")
  end

  slot(:action, doc: "the slot for showing user actions in the last table column")
  slot(:empty, doc: "row shown in a sibling tbody when the caller decides the table is empty")

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class={["overflow-x-auto", @framed && "rounded-xl border border-line bg-surface"]}>
      <table class="w-full text-left text-sm">
        <caption :if={@caption} class="sr-only">{@caption}</caption>
        <thead class="border-b border-line bg-surface-sunken">
          <tr>
            <th
              :for={col <- @col}
              scope="col"
              aria-sort={table_aria_sort(col[:sort], @sort_by, @sort_dir)}
              class={[
                "px-2 py-1.5 text-xs font-semibold text-ink-subtle",
                col[:align] == :right && "text-right"
              ]}
            >
              <.table_sort_heading
                :if={col[:sort]}
                col={col}
                table_id={@id}
                sort_by={@sort_by}
                sort_dir={@sort_dir}
                sort_event={@sort_event}
              />
              <span :if={!col[:sort]}>{col[:label]}</span>
            </th>
            <th :if={@action != []} scope="col" class="px-2 py-1.5">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-low-contrast-line"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="hover:bg-surface-sunken">
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "px-2 py-0.5 text-ink",
                col[:align] == :right && "text-right",
                @row_click && "hover:cursor-pointer"
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 px-2 py-0.5 font-semibold">
              <div class="flex items-center justify-end gap-1">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
        <tbody :if={@empty != []}>
          <tr id={"#{@id}-empty"}>
            <td
              colspan={table_empty_colspan(@col, @action)}
              class="px-2 py-8 text-center text-sm text-ink-muted"
            >
              {render_slot(@empty)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders an inline-editable text cell (Belimbing inline-edit pattern).

  In display mode, shows the text with a pencil icon that appears on hover.
  Clicking immediately reveals an input box. On blur or Enter, it commits the
  change and pushes `@save_event` to LiveView with `%{id: @id_value, <@name>: new_value}`.
  Pressing Escape cancels and reverts to the original value without pushing.

  ## Examples

      <.inline_edit
        id={"country-\#{country.id}-name"}
        value={country.country}
        id_value={country.id}
        save_event="save-country-name"
        name="country"
        label="Country name"
      />
  """
  attr(:id, :string, required: true)
  attr(:value, :string, required: true)
  attr(:id_value, :any, default: nil)
  attr(:save_event, :string, default: "save")
  attr(:name, :string, default: "value")
  attr(:label, :string, default: "Edit value")
  attr(:class, :any, default: nil)
  attr(:input_class, :any, default: nil)
  attr(:rest, :global)

  def inline_edit(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="InlineEdit"
      data-id={@id_value || @id}
      data-field={@name}
      data-save-event={@save_event}
      class={["relative min-w-0 max-w-full text-sm text-ink", @class]}
      {@rest}
    >
      <button
        type="button"
        data-role="trigger"
        aria-label={@label}
        class="group flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 -mx-1.5 text-left hover:bg-surface-sunken transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
      >
        <span data-role="text" class="text-ink">{@value}</span>
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
        aria-label={@label}
        class={[
          "absolute left-0 top-0 hidden w-full min-w-0 max-w-full box-border rounded border border-brand-strong bg-surface px-1.5 py-0.5 -mx-1.5 text-sm text-ink focus:outline-none focus:border-brand-strong focus:ring-1 focus:ring-brand-strong/30",
          @input_class
        ]}
      />
    </div>
    """
  end

  attr(:col, :map, required: true)
  attr(:table_id, :string, required: true)
  attr(:sort_by, :any, required: true)
  attr(:sort_dir, :any, required: true)
  attr(:sort_event, :string, default: "sort")

  defp table_sort_heading(assigns) do
    ~H"""
    <button
      id={@col[:sort_id] || "#{@table_id}-sort-#{@col[:sort]}"}
      type="button"
      phx-click={@sort_event}
      phx-value-sort={@col[:sort]}
      class={[
        "inline-flex items-center gap-1 rounded transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong/30",
        @col[:align] == :right && "ml-auto",
        @col[:align] != :right && "text-left"
      ]}
    >
      {@col[:label]}
      <.icon
        name={table_sort_icon(@col[:sort], @sort_by, @sort_dir)}
        class={["size-3.5", table_sort_active?(@col[:sort], @sort_by) && "text-action"]}
      />
    </button>
    """
  end

  defp table_aria_sort(nil, _sort_by, _sort_dir), do: nil

  defp table_aria_sort(sort, sort_by, sort_dir) do
    cond do
      not table_sort_active?(sort, sort_by) -> "none"
      table_sort_dir(sort_dir) == :asc -> "ascending"
      table_sort_dir(sort_dir) == :desc -> "descending"
      true -> "none"
    end
  end

  defp table_sort_icon(sort, sort_by, sort_dir) do
    cond do
      not table_sort_active?(sort, sort_by) -> "sort"
      table_sort_dir(sort_dir) == :asc -> "sort-asc"
      table_sort_dir(sort_dir) == :desc -> "sort-desc"
      true -> "sort"
    end
  end

  defp table_sort_active?(sort, sort_by), do: to_string(sort) == to_string(sort_by)

  defp table_sort_dir(dir) when dir in ["asc", :asc], do: :asc
  defp table_sort_dir(dir) when dir in ["desc", :desc], do: :desc
  defp table_sort_dir(_dir), do: nil

  defp table_empty_colspan(cols, action) when action == [], do: length(cols)
  defp table_empty_colspan(cols, _action), do: length(cols) + 1

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-low-contrast-line text-sm">
      <div :for={item <- @item} class="flex items-baseline justify-between gap-6 py-2.5">
        <dt class="font-medium text-ink-subtle">{item.title}</dt>
        <dd class="text-right text-ink">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a named action icon or a [Heroicon](https://heroicons.com).

  Prefer a name from `Bilimbi.Base.UI.IconRegistry` so the action meaning is
  explicit. Unknown names beginning with `hero-` still pass through to
  generated Heroicons. Custom product glyphs such as `bilimbi-pin` render as
  inline SVG. A name that is neither registered nor `hero-`-prefixed raises
  `ArgumentError` rather than rendering a meaningless fallback glyph; pass a
  name that came from stored data through `IconRegistry.renderable?/1` first.

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="close" />
      <.icon name="refresh" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr(:name, :string, required: true)
  attr(:class, :any, default: "size-4")

  def icon(assigns) do
    case IconRegistry.lookup(assigns.name) do
      {:svg, icon} -> registered_icon(assign(assigns, :icon, icon))
      {:hero, hero_name} -> hero_icon(assign(assigns, :name, hero_name))
      :error -> hero_icon(assigns)
    end
  end

  defp registered_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      viewBox={@icon.view_box}
      fill={@icon.fill}
      stroke={@icon.fill == "none" && "currentColor"}
      stroke-width={@icon.fill == "none" && "1.5"}
      aria-hidden="true"
    >
      <path
        :for={path <- @icon.paths}
        stroke-linecap="round"
        stroke-linejoin="round"
        d={path}
      />
    </svg>
    """
  end

  defp hero_icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  defp hero_icon(assigns), do: hero_icon(assign(assigns, :name, "hero-square-3-stack-3d"))

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
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(Bilimbi.Base.UI.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Bilimbi.Base.UI.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
