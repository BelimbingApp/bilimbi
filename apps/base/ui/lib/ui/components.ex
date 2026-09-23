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

  attr(:selection_label, :string,
    default: nil,
    doc: "the singular|plural summary template for a `multi_select` input"
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

  attr(:reveal, :any,
    default: false,
    doc: """
    adds a show/hide control to a `password` input. `false` keeps the value
    masked with no control, which is right for sign-in. `true` names the value
    a secret; a string such as `"password"` or `"API key"` is the noun the
    control's accessible name uses instead. Any other type rejects it.
    """
  )

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

  def input(%{reveal: reveal, type: type})
      when reveal not in [false, nil] and type != "password" do
    raise ArgumentError,
          "reveal only applies to a password input; got reveal=#{inspect(reveal)} on type=#{inspect(type)}"
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
          aria-invalid={@errors != [] && "true"}
          aria-describedby={described_by(@id, @hint, @errors)}
          class={
            @class ||
              [
                "size-4 shrink-0 rounded accent-action focus:outline-none focus:ring-2",
                field_state_class(@errors, "border-high-contrast-line focus:ring-brand-strong/30")
              ]
          }
          {@rest}
        />{@label}<span :if={@rest[:required]} aria-hidden="true">*</span>
      </label>
      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
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
        {@label}<span :if={@rest[:required]} aria-hidden="true">*</span>
      </label>
      <select
        id={@id}
        name={@name}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @hint, @errors)}
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
      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "multi_select"} = assigns) do
    {required, rest} = Map.pop(assigns.rest, :required, false)

    # `placeholder` names the empty-selection summary here rather than an HTML
    # attribute, and a button has none to render. An absent key lets
    # `multi_select/1` merge its own declared default; a nil one replaces that
    # default with nothing, so what the caller omitted is dropped outright.
    {placeholder, rest} = Map.pop(rest, :placeholder)

    {omitted, supplied} =
      Enum.split_with(
        [placeholder: placeholder, selection_label: assigns.selection_label],
        fn {_key, value} -> is_nil(value) end
      )

    assigns
    |> Map.drop(Keyword.keys(omitted))
    |> assign(required: required == true, rest: rest)
    |> assign(supplied)
    |> multi_select()
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <label
        :if={@label}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}<span :if={@rest[:required]} aria-hidden="true">*</span>
      </label>
      <textarea
        id={@id}
        name={@name}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @hint, @errors)}
        class={
          field_class(@class, @error_class, @errors, extra: "min-h-24", readonly: @rest[:readonly])
        }
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
    </div>
    """
  end

  # A secret whose caller asked for a reveal control. The toggle is a real
  # button whose accessible name states the action and the current state.
  #
  # The input's own `type` is the only record of masked-or-shown, and the
  # click is the single JS command that flips it. LiveView keeps that
  # attribute sticky across patches, so a form re-render never silently
  # re-masks a value the user chose to see. The button's accessible name,
  # title and glyph are derived from `type` by the `SecretReveal` hook rather
  # than swapped alongside it: LiveView applies an attribute op synchronously
  # but defers a class op to a later animation frame, so toggling both at once
  # could invert them -- two clicks inside one frame flipped `type` twice and
  # the glyph once, leaving a masked input showing the "hide" eye with no path
  # back. The hook also keeps a pointer press from pulling focus out of the
  # input.
  def input(%{type: "password", reveal: reveal} = assigns) when reveal not in [false, nil] do
    subject = if is_binary(reveal), do: reveal, else: gettext("secret")
    show_label = gettext("Show %{subject}, currently hidden", subject: subject)
    hide_label = gettext("Hide %{subject}, currently shown", subject: subject)
    show_title = gettext("Show %{subject}", subject: subject)
    hide_title = gettext("Hide %{subject}", subject: subject)

    assigns =
      assigns
      |> assign(:show_label, show_label)
      |> assign(:hide_label, hide_label)
      |> assign(:show_title, show_title)
      |> assign(:hide_title, hide_title)
      |> assign(:toggle, JS.toggle_attribute({"type", "text", "password"}, to: "##{assigns.id}"))

    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <label
        :if={@label}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}
      </label>
      <div class="flex items-center">
        <input
          type="password"
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[field_class(@class, @error_class, @errors), "pr-10"]}
          {@rest}
        />
        <button
          id={"#{@id}-reveal"}
          type="button"
          phx-hook="SecretReveal"
          phx-click={@toggle}
          aria-label={@show_label}
          aria-controls={@id}
          title={@show_title}
          data-show-label={@show_label}
          data-hide-label={@hide_label}
          data-show-title={@show_title}
          data-hide-title={@hide_title}
          disabled={@rest[:disabled]}
          class="-ml-[1.875rem] grid size-6 shrink-0 place-items-center rounded-sm text-ink-muted transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50 disabled:text-ink-faint"
        >
          <span id={"#{@id}-reveal-show"} class="grid">
            <.icon name="reveal" class="size-4" />
          </span>
          <span id={"#{@id}-reveal-hide"} class="grid hidden">
            <.icon name="conceal" class="size-4" />
          </span>
        </button>
      </div>
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
        {@label}<span :if={@rest[:required]} aria-hidden="true">*</span>
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @hint, @errors)}
        class={field_class(@class, @error_class, @errors, readonly: @rest[:readonly])}
        {@rest}
      />
      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
    </div>
    """
  end

  # Relationships a person depends on: hint and error text must be announced
  # with the control, not stranded beside it. Returns the space-separated id
  # list for `aria-describedby`, or nil when there is nothing to point at so
  # no dangling reference is rendered.
  defp described_by(id, hint, errors) do
    error_ids = errors |> Enum.with_index() |> Enum.map(fn {_, i} -> "#{id}-error-#{i}" end)

    [if(hint, do: "#{id}-hint") | error_ids]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  # One control family for every field type. `class` replaces the default
  # entirely; `error_class` replaces only the invalid-state styling.
  defp field_class(class, error_class, errors, opts \\ []) do
    [
      class || field_base_class(opts[:readonly]),
      is_nil(class) && opts[:extra],
      field_state_class(errors, "border-high-contrast-line", error_class)
    ]
  end

  # A field in error reads the same whichever control draws it, so the invalid
  # appearance is decided once here rather than per control family.
  defp field_state_class(errors, valid_class, error_class \\ nil)
  defp field_state_class([], valid_class, _error_class), do: valid_class

  defp field_state_class(_errors, _valid_class, error_class),
    do: error_class || "border-danger focus:border-danger focus:ring-danger/20"

  # `readonly` is a statement the caller made about this field. The CSS
  # `:read-only` pseudo-class is not the same statement: it matches every
  # immutable control, including every `select`, `color` and `file` input.
  defp field_base_class(readonly, padding \\ "px-3") do
    "block w-full rounded-md border #{padding} py-1.5 text-sm text-ink shadow-xs " <>
      "transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none " <>
      "focus:ring-2 focus:ring-brand-strong/30 disabled:cursor-not-allowed " <>
      "disabled:bg-surface-sunken disabled:text-ink-subtle " <>
      if(readonly, do: "bg-surface-sunken", else: "bg-surface")
  end

  @doc """
  Renders a multi-select dropdown component (Belimbing's `x-ui.multi-select` counterpart).

  Displays a button showing the selection summary (e.g. "All roles", "1 role selected",
  or "3 roles selected") with a chevron icon, and toggles a floating menu containing
  checkboxes for each option.

  The trigger's `aria-expanded` follows the menu. Clicking the trigger again,
  clicking outside, or moving focus out of the field closes it. While it is
  open, Escape closes it from anywhere on the page; focus returns to the
  trigger only when focus was already inside the field, and otherwise stays
  where the user put it.

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
  attr(:required, :boolean, default: false)
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

    # `aria-expanded` follows the list because the same command moves both.
    # Click-away sits on the wrapper: LiveView dispatches click-away before
    # the click it belongs to, so a click-away on the list itself would close
    # and the trigger's toggle would reopen in the same click. Escape is the
    # only path that returns focus to the trigger, and only from a press that
    # was already inside the field: the hook runs plain `dismiss` otherwise,
    # so Escape typed into a search box elsewhere on the page closes the list
    # without taking the caret. Every other path leaves focus where the user
    # put it.
    #
    # Dismiss and escape are published on the wrapper for the
    # `MultiSelectDismiss` hook, which owns the two dismissals LiveView has
    # no binding for: focus leaving the field, and Escape from wherever focus
    # actually is -- a list opened by mouse in Safari or macOS Firefox is open
    # with focus still on `body`. LiveView reads a key binding from the event
    # target alone, so an element-level `phx-keydown` here would also stop
    # every key ever reaching the page's `phx-window-keydown` handlers. The
    # list is focusable so a click on its padding lands inside the field
    # rather than on `body`.
    #
    # The trigger carries `aria-expanded` and `aria-controls` and no
    # `aria-haspopup`: the list is a disclosure of checkboxes, not a menu, and
    # `aria-haspopup="true"` would announce menu semantics with arrow-key
    # navigation that nothing here implements.
    #
    # The trigger's `aria-expanded` is the only record of open, and every
    # command below writes that one attribute and nothing else. The list's
    # visibility and the chevron's rotation are CSS derived from it through
    # the `peer`/`group` relationships the markup already has, so they cannot
    # disagree with it. Toggling them alongside the attribute is what they
    # used to do, and it could invert: LiveView applies an attribute op
    # synchronously but defers a class op to a later animation frame, so two
    # activations landing in one frame flipped the attribute twice and the
    # classes once, leaving an open list announcing `aria-expanded="false"`.
    # Deriving is also why the accessible state survives a patch for free --
    # only the attribute has to be sticky.
    id = assigns.id

    dismiss = JS.set_attribute({"aria-expanded", "false"}, to: "##{id}")
    toggle = JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}")

    assigns =
      assigns
      |> assign(:input_name, input_name)
      |> assign(:selected_values, selected_values)
      |> assign(:normalized_options, normalized_options)
      |> assign(:selected_count, selected_count)
      |> assign(:summary_label, summary_label)
      |> assign(:dismiss, dismiss)
      |> assign(:toggle, toggle)
      |> assign(:escape, JS.focus(dismiss, to: "##{id}"))

    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="MultiSelectDismiss"
      data-dismiss={@dismiss}
      data-escape={@escape}
      phx-click-away={@dismiss}
      class={["relative", @wrapper_class || "mb-4"]}
    >
      <input type="hidden" name={@input_name} value="" />
      <label
        :if={@label}
        id={"#{@id}-label"}
        for={@id}
        class={["mb-1.5 block text-sm font-medium text-ink", @label_class]}
      >
        {@label}<span :if={@required} aria-hidden="true">*</span>
      </label>

      <button
        id={@id}
        type="button"
        aria-expanded="false"
        aria-controls={"#{@id}-options"}
        aria-required={@required && "true"}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @hint, @errors)}
        phx-click={@toggle}
        class={[
          "peer group flex w-full items-center justify-between gap-3 rounded-md border bg-surface py-1.5 px-3 text-left text-sm text-ink shadow-xs transition hover:bg-surface-muted focus:outline-none focus:ring-2",
          field_state_class(
            @errors,
            "border-line focus:border-brand-strong focus:ring-brand-strong/30"
          ),
          @class
        ]}
        {@rest}
      >
        <span class="truncate font-normal">
          {@summary_label}
        </span>
        <span
          id={"#{@id}-chevron"}
          class="inline-flex shrink-0 transition-transform duration-200 group-aria-expanded:rotate-180"
        >
          <.icon
            name="hero-chevron-down"
            class="size-4 text-ink-muted"
          />
        </span>
      </button>

      <div
        id={"#{@id}-options"}
        tabindex="-1"
        class="hidden peer-aria-expanded:block absolute left-0 z-30 mt-1 max-h-60 w-full min-w-56 overflow-y-auto rounded-xl border border-line bg-surface p-1.5 shadow-lg space-y-0.5 focus:outline-none"
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

      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
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
          class={field_base_class(false, "pl-8 pr-3")}
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
    format = assigns.format

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

  defp server_datetime(value, :date), do: Calendar.strftime(value, "%d/%m/%Y UTC")
  defp server_datetime(value, :time), do: Calendar.strftime(value, "%H:%M UTC")
  defp server_datetime(value, :datetime), do: Calendar.strftime(value, "%d/%m/%Y, %H:%M UTC")

  defp zoned_datetime(value, :date), do: Calendar.strftime(value, "%d/%m/%Y ") <> value.zone_abbr
  defp zoned_datetime(value, :time), do: Calendar.strftime(value, "%H:%M ") <> value.zone_abbr

  defp zoned_datetime(value, :datetime),
    do: Calendar.strftime(value, "%d/%m/%Y, %H:%M ") <> value.zone_abbr

  # Helper used by inputs to generate form errors
  attr(:id, :string, default: nil)
  slot(:inner_block, required: true)

  defp error(assigns) do
    ~H"""
    <p id={@id} class="mt-1.5 flex items-center gap-1.5 text-sm text-danger-ink">
      <.icon name="error" class="size-4 shrink-0 text-danger" />
      {render_slot(@inner_block)}
    </p>
    """
  end

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

  # The default gives way only to a base-variant padding shorthand. A
  # responsive one (`sm:p-6`) sets nothing below its breakpoint, and an
  # axis-only one (`px-4`) sets nothing on the other axis, so both keep it.
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
  the round trip, so it reads "Deleting…" and is announced busy until the
  server replies.

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
  defp page_width(:detail), do: "max-w-7xl"

  @doc """
  Renders a header with title.

  With `actions`, the title block and the actions row share one line from
  the `sm` breakpoint and stack — title first, actions below — on a phone,
  as Belimbing's `x-ui.page-header` does, so a labelled actions row never
  squeezes the title into one word per line or clips at the viewport edge.
  """
  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:title_actions)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-6",
      "pb-4"
    ]}>
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
  Renders a table with compact Belimbing-parity styling and a flat outer frame.

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

  attr(:sort_target, :any,
    default: nil,
    doc: "`phx-target` for the sort event; a LiveComponent passes `@myself`, a LiveView nothing"
  )

  attr(:framed, :boolean,
    default: true,
    doc: "when false, omit the flat outer frame so the table can sit in an existing panel"
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

  slot :empty,
    doc: """
    row shown in a sibling tbody when the caller decides the table is empty.
    Plain content renders as given. With `title` or `forbidden` the row is an
    `empty_state/1` and the slot body is its recovery action, so a table says
    what is missing and why without a second component.
    """ do
    attr(:title, :string, doc: "what is missing, as `empty_state/1` takes it")
    attr(:reason, :string, doc: "why it is missing")
    attr(:forbidden, :string, doc: "the action the actor lacks permission for")
  end

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class={["overflow-x-auto", @framed && "border border-line bg-surface"]}>
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
                sort_target={@sort_target}
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
              <%= for empty <- @empty do %>
                <%= if empty[:title] || empty[:forbidden] do %>
                  <.empty_state
                    title={empty[:title]}
                    reason={empty[:reason]}
                    forbidden={empty[:forbidden]}
                  >
                    <:action :if={empty[:inner_block]}>{render_slot(empty)}</:action>
                  </.empty_state>
                <% else %>
                  {render_slot(empty)}
                <% end %>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders an empty region: what is missing, why it is missing, and an
  optional way to recover.

  A region with nothing to show is one of three situations, and the person in
  front of it has to tell them apart because each asks something different of
  them:

    * nothing has been created yet: `title` and `reason`, usually with the
      action that creates the first record;
    * a search or filter matched nothing: `title` and `reason`, with the
      action that clears it;
    * they may not look: `forbidden`.

  The first two are the caller's own sentences, and they must not be one
  sentence. The third is one wording owned here so that every region that is
  out of reach says the same plain thing: "You do not have permission to
  <forbidden>." followed by the recovery, "Ask an operator to review your
  role." It does not suggest trying again and it does not imply the data is
  absent.

  `title` and `forbidden` are the two modes, and a call gives one of them: a
  region either says what is missing or says it is out of reach.

  `<.table>` reaches this from its `<:empty>` slot, so a table needs no second
  component. The block carries no padding of its own; the table cell or the
  caller's region supplies it.

  ## Examples

      <.empty_state title="No companies yet" reason="Companies you create appear here.">
        <:action>
          <.button variant="primary" navigate={~p"/companies/create"}>Add Company</.button>
        </:action>
      </.empty_state>

      <.empty_state title="No companies match “acme”" reason="Clear the search to see every company.">
        <:action><.button patch={~p"/companies"}>Clear search</.button></:action>
      </.empty_state>

      <.empty_state forbidden="view companies" />
  """
  attr(:id, :string, default: nil)

  attr(:title, :string,
    default: nil,
    doc: "what is missing; give this or `forbidden`, never both"
  )

  attr(:reason, :string, default: nil, doc: "why it is missing")

  attr(:forbidden, :string,
    default: nil,
    doc: "the action the actor lacks permission for, such as \"view companies\""
  )

  attr(:class, :any, default: nil)

  slot(:action,
    doc: "an optional recovery, such as clearing the search or creating the first record"
  )

  def empty_state(%{title: nil, forbidden: nil}) do
    raise ArgumentError,
          "<.empty_state> needs a title (what is missing) or forbidden (the action the actor lacks)"
  end

  def empty_state(%{title: title, forbidden: forbidden})
      when is_binary(title) and is_binary(forbidden) do
    raise ArgumentError,
          "<.empty_state> takes a title (what is missing) or forbidden (the action the actor lacks), not both"
  end

  def empty_state(assigns) do
    assigns = assign(assigns, empty_state_copy(assigns))

    ~H"""
    <div id={@id} class={["text-center text-sm", @class]}>
      <p class="font-medium text-ink">{@heading}</p>
      <p :for={line <- @details} class="mt-1 text-ink-muted">{line}</p>
      <div :if={@action != []} class="mt-3 flex flex-wrap items-center justify-center gap-2">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  # The one permission wording. A region the actor may not see states that
  # plainly and names the recovery; it never says to try again, and never
  # implies the records do not exist.
  defp empty_state_copy(%{title: nil, forbidden: forbidden}) do
    %{heading: permission_wording(forbidden), details: [permission_recovery()]}
  end

  defp empty_state_copy(%{title: title, reason: reason, forbidden: nil}) do
    %{heading: title, details: Enum.reject([reason], &is_nil/1)}
  end

  defp permission_wording(action), do: "You do not have permission to #{action}."
  defp permission_recovery, do: "Ask an operator to review your role."

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
  Back) with no button among them.

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
  in `text-link` that darkens on hover, never a button.

  `<.back_link>` and `<.action_link>` are the link members of the family and
  apply it themselves. It is public for the one member that is structurally
  not a link: the `record.history` trigger is the `<summary>` of a
  `<details>` and takes this class so History sits in the header row as the
  same kind of thing as Impersonate and Back, as Belimbing's
  `admin/*/show` pages present it. Do not use it to style a button as a
  link; a control that changes data is a `<.button>`.
  """
  @spec demoted_action_class() :: String.t()
  def demoted_action_class do
    "inline-flex items-center gap-1 whitespace-nowrap text-sm text-link transition-colors hover:text-ink focus-visible:outline-none focus-visible:rounded-sm focus-visible:ring-1 focus-visible:ring-brand-strong/40"
  end

  attr(:col, :map, required: true)
  attr(:table_id, :string, required: true)
  attr(:sort_by, :any, required: true)
  attr(:sort_dir, :any, required: true)
  attr(:sort_event, :string, default: "sort")
  attr(:sort_target, :any, default: nil)

  defp table_sort_heading(assigns) do
    ~H"""
    <button
      id={@col[:sort_id] || "#{@table_id}-sort-#{@col[:sort]}"}
      type="button"
      phx-click={@sort_event}
      phx-target={@sort_target}
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
  Renders the facts of one record as a definition list.

  This is the one shape a detail page's facts take. Each item is a row: the
  label sits in a fixed left column and the value fills the rest, left-aligned,
  so a value reads in the same place whether it is a word, a badge, a link or
  an in-place editor. The value cell is a block the width of the row, which is
  what lets `<.inline_edit>` open its input at full width and report its
  commit status underneath; a right-aligned, shrink-wrapped value cannot host
  one. Below the `sm` breakpoint the label stacks above its value.

  Pass `id` on the list so it can be found. Pass `id` on an item to name its
  value cell. Tests and `aria-describedby` references read the value, not the
  row, so the id lands on the `<dd>`; an item without one renders no `id`.

  ## Examples

      <.list id="address-facts">
        <:item title="Company">{@company.name}</:item>
        <:item title="Status"><.badge kind={:success}>Active</.badge></:item>
        <:item title="Label" id="address-view-label">
          <.inline_edit id="address-label" value={@address.label || ""} allow_empty ... />
        </:item>
      </.list>
  """
  attr(:id, :string, default: nil)

  slot :item, required: true do
    attr(:title, :string, required: true)
    attr(:id, :string, doc: "DOM id of the value cell (the `<dd>`)")
  end

  def list(assigns) do
    ~H"""
    <dl id={@id} class="divide-y divide-low-contrast-line text-sm">
      <div
        :for={item <- @item}
        class="grid grid-cols-1 gap-x-6 gap-y-1 py-2.5 sm:grid-cols-[10rem_minmax(0,1fr)] sm:items-baseline"
      >
        <dt class="font-medium text-ink-subtle">{item.title}</dt>
        <dd id={item[:id]} class="min-w-0 text-ink">{render_slot(item)}</dd>
      </div>
    </dl>
    """
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
