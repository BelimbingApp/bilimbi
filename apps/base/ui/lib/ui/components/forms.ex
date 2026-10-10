defmodule Bilimbi.Base.UI.Components.Forms do
  @moduledoc """
  Form controls: `secret_input/1`, `input/1`, `combobox/1`, `multi_select/1`
  and `radio_group/1`, with the field classes, described-by wiring and error
  translation they share.

  `use Bilimbi.Base.UI.Components` imports it with the rest.
  """
  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Bilimbi.Base.UI.Components.Icon

  alias Phoenix.LiveView.JS

  @doc """
  Renders a field the viewer may not see.

  Field-level authorization withholds one value from someone who may open
  the rest of the record (`Bilimbi.Base.Authz.redact/3` puts a
  `Bilimbi.Base.Authz.Restricted` marker in the field's place). This is how
  that marker reads: the word "Restricted" with the registry's `restricted`
  lock, and the reason in its tooltip and accessible description, so a field
  that is withheld and a field that is empty never look alike. An empty
  field reads "—"; this reads as a value the person is not shown. It carries
  no editor and no copy button, and a page never renders an in-place control
  around it: an editor cannot show what it would replace. In a create or
  edit form the same field is `<.restricted_field>`, a read-only row, never
  an omitted input.

  The tooltip says plainly what is true: "You don't have access to this
  field." A field is restricted for roles the person holds
  (`Bilimbi.Base.Authz.Restricted`), so naming roles here would name their
  own; there is nothing to ask for. `reason` replaces the sentence when a
  page has a better one.

  ## Examples

      <.restricted id="detail-email-restricted" />
      <.restricted id="salary-restricted" reason="Salaries are shown to payroll only." />
  """
  attr(:id, :string, required: true)

  attr(:reason, :string,
    default: nil,
    doc: "a page's own sentence for why the value is withheld; replaces the default tooltip"
  )

  attr(:class, :any, default: nil)

  def restricted(assigns) do
    assigns = assign(assigns, :tooltip, assigns.reason || restricted_reason())

    ~H"""
    <span
      id={@id}
      data-restricted
      title={@tooltip}
      aria-description={@tooltip}
      class={["inline-flex items-center gap-1 text-ink-muted", @class]}
    >
      <.icon name="restricted" class="size-4" />
      <span>{gettext("Restricted")}</span>
    </span>
    """
  end

  @doc "The one sentence a restricted field explains itself with."
  @spec restricted_reason() :: String.t()
  def restricted_reason, do: gettext("You don't have access to this field.")

  @doc """
  A form row for a field the person may not see.

  A create or edit form never omits a restricted field, and never renders an
  input for it: an omitted field reads as "this form has no such field", and
  an input would offer a write the module refuses. Instead the row keeps its
  label and shows a greyed, read-only value cell carrying `<.restricted>`,
  with the same tooltip, so the form reads the same as the record page. It
  renders no `<input>` and no `name`, so nothing is submitted for the field;
  the owning module still refuses a value a forged submit sends
  (`Bilimbi.Base.Authz.refuse_restricted_attempts/4`).

  ## Examples

      <.restricted_field id="company-email" label="Email" />
  """
  attr(:id, :string, required: true)
  attr(:label, :string, required: true)

  attr(:reason, :string,
    default: nil,
    doc: "a page's own sentence, replacing the default tooltip"
  )

  attr(:wrapper_class, :any, default: nil)

  def restricted_field(assigns) do
    assigns = assign(assigns, :tooltip, assigns.reason || restricted_reason())

    ~H"""
    <div id={@id} class={@wrapper_class || "mb-4"} data-restricted-field>
      <span id={"#{@id}-label"} class="mb-1.5 block text-sm font-medium text-ink">{@label}</span>
      <div
        id={"#{@id}-value"}
        role="group"
        aria-labelledby={"#{@id}-label"}
        aria-readonly="true"
        aria-description={@tooltip}
        title={@tooltip}
        class="flex min-h-10 w-full items-center rounded-lg border border-line bg-surface-sunken px-3 py-2 text-sm text-ink-muted"
      >
        <.restricted id={"#{@id}-restricted"} reason={@reason} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a masked secret field with a reveal control by default.

  `subject` is the noun used by the control's accessible name. For a stored
  encrypted value, pass `stored?={true}` and the owner's keep-current `mask`.
  The component discards `value` in that state: plaintext must never be sent
  back to the browser. The Clear button empties the live input, so submitting
  it lets the owning form apply its explicit clear policy. A reveal of the
  keep-current mask reveals only the mask, never the stored value.
  """
  attr(:field, Phoenix.HTML.FormField, default: nil)
  attr(:id, :string, default: nil)
  attr(:name, :string, default: nil)
  attr(:value, :any, default: nil)
  attr(:label, :string, default: nil)
  attr(:subject, :string, required: true)
  attr(:reveal, :boolean, default: true)
  attr(:stored?, :boolean, default: false)
  attr(:stored_reveal, :map, default: nil)
  attr(:mask, :string, default: "••••••••")
  attr(:hint, :string, default: nil)
  attr(:wrapper_class, :any, default: nil)
  attr(:class, :any, default: nil)

  attr(:rest, :global,
    include:
      ~w(autocomplete disabled form maxlength minlength pattern placeholder readonly required)
  )

  def secret_input(assigns) do
    assigns =
      assigns
      |> assign(
        :secret_value,
        if(assigns.stored?,
          do: assigns.mask,
          else: assigns.value || (assigns.field && assigns.field.value)
        )
      )
      |> assign(:secret_name, assigns.name || (assigns.field && assigns.field.name))
      |> assign(:secret_id, assigns.id || (assigns.field && assigns.field.id) || assigns.name)
      |> assign(:autocomplete, assigns.rest[:autocomplete] || "new-password")
      |> assign(:input_rest, Map.delete(assigns.rest, :autocomplete))

    ~H"""
    <div class={@wrapper_class || "mb-4"}>
      <.input
        field={@field}
        id={@secret_id}
        name={@secret_name}
        value={@secret_value}
        type="password"
        label={@label}
        reveal={@reveal && @subject}
        hint={@hint}
        class={@class}
        wrapper_class={if @stored?, do: "mb-1.5", else: "mb-0"}
        autocomplete={@autocomplete}
        phx-hook={@stored? && "SecretStored"}
        {@input_rest}
      />
      <button
        :if={@stored? && @stored_reveal}
        id={"#{@secret_id}-show-stored"}
        type="button"
        phx-click={@stored_reveal.event}
        phx-value-key={@stored_reveal.key}
        class="mr-3 text-xs font-medium text-ink hover:underline focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40"
      >
        {gettext("Show stored value")}
      </button>
      <button
        :if={@stored?}
        id={"#{@secret_id}-clear"}
        type="button"
        phx-hook="SecretClear"
        data-input-id={@secret_id}
        disabled={@rest[:disabled] || @rest[:readonly]}
        class="text-xs font-medium text-danger-ink hover:underline focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:opacity-50"
      >
        {gettext("Clear %{subject}", subject: @subject)}
      </button>
    </div>
    """
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

  attr(:multiple, :boolean,
    default: false,
    doc: "the multiple flag for select inputs; the listbox shows five rows"
  )

  attr(:selection_label, :string,
    default: nil,
    doc: "the singular|plural summary template for a `multi_select` input"
  )

  attr(:chips, :boolean,
    default: false,
    doc: "for a `multi_select` input: show each selected option as a removable chip"
  )

  attr(:on_remove, JS,
    default: nil,
    doc: "for a `multi_select` input with `chips`: the command a chip's remove button runs"
  )

  attr(:class, :any, default: nil, doc: "the input class to use over defaults")

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
            field_class(@class, @errors),
            # A listbox is sized in rows, not pixels. `py-2` makes the box taller
            # than the rows it holds, and the browser fills the slack with the
            # *next* option -- so the last row is painted sliced through its
            # glyphs and reads as a rendering fault rather than "scroll for more"
            # (#281). Height comes from the five-row `size` instead.
            @multiple && "!py-0"
          ]
        }
        multiple={@multiple}
        size={@multiple && 5}
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
        class={field_class(@class, @errors, extra: "min-h-24", readonly: @rest[:readonly])}
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
          aria-invalid={@errors != [] && "true"}
          aria-describedby={described_by(@id, @hint, @errors)}
          class={[field_class(@class, @errors), "pr-10"]}
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
      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
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
        class={field_class(@class, @errors, readonly: @rest[:readonly])}
        {@rest}
      />
      <p :if={@hint} id={"#{@id}-hint"} class="mt-1.5 text-xs text-ink-subtle">{@hint}</p>
      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={"#{@id}-error-#{i}"}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a single-value combobox backed by a hidden form field.

  The visible text input is deliberately unnamed: the `Combobox` hook filters
  and navigates the rendered options, then copies only a committed option's
  value into the hidden field. That keeps form params and changeset validation
  identical to the native select this replaces. Escape and leaving the field
  restore the last committed option; a caller that supplies `cancel_event`
  also receives that event so an inline editor can leave edit mode.

  Options are `{label, value}` pairs. An empty option list says that choices
  are unavailable, while a query with no matches says that the filter found
  nothing. The control follows the ARIA combobox/listbox pattern and keeps
  `aria-activedescendant` on the text input as the active option changes.
  """
  attr(:id, :string, default: nil)
  attr(:name, :string, default: nil)
  attr(:label, :string, default: nil)
  attr(:value, :any, default: nil)
  attr(:field, Phoenix.HTML.FormField, default: nil)
  attr(:options, :list, default: [])
  attr(:placeholder, :string, default: "")
  attr(:errors, :list, default: [])
  attr(:cancel_event, :string, default: nil)
  attr(:wrapper_class, :any, default: nil)

  attr(:rest, :global,
    include:
      ~w(aria-label aria-labelledby autofocus autocomplete form maxlength minlength placeholder readonly)
  )

  def combobox(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []
    value = if is_nil(assigns.value), do: field.value, else: assigns.value

    assigns
    |> assign(
      field: nil,
      id: assigns.id || field.id,
      name: assigns.name || field.name,
      value: value
    )
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> combobox()
  end

  def combobox(%{id: nil, name: name} = assigns) when is_binary(name) do
    assigns |> assign(:id, name) |> combobox()
  end

  def combobox(assigns) do
    options = normalize_choice_options(assigns.options)
    value = if is_nil(assigns.value), do: "", else: to_string(assigns.value)

    selected_label =
      Enum.find_value(options, "", fn {label, option} -> if option == value, do: label end)

    described_by = described_by(assigns.id, nil, assigns.errors)

    assigns =
      assigns
      |> assign(:normalized_options, options)
      |> assign(:value_string, value)
      |> assign(:selected_label, selected_label)
      |> assign(:described_by, described_by)

    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="Combobox"
      data-value-id={"#{@id}-value"}
      data-cancel-event={@cancel_event}
      class={["relative floating-scope", @wrapper_class || "mb-4"]}
    >
      <%!-- `hidden` keeps the committed value out of the visual UI while leaving
      the field fillable by Phoenix.LiveViewTest like a browser text input. --%>
      <input
        type="text"
        hidden
        id={"#{@id}-value"}
        name={@name}
        value={@value_string}
      />
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-medium text-ink">
        {@label}
      </label>

      <div class="relative floating-anchor">
        <input
          id={@id}
          type="text"
          role="combobox"
          aria-autocomplete="list"
          aria-controls={"#{@id}-options"}
          aria-expanded="false"
          aria-invalid={@errors != [] && "true"}
          aria-describedby={@described_by}
          autocomplete="off"
          value={@selected_label}
          placeholder={@placeholder}
          class={[field_class(nil, @errors), "pr-9"]}
          {@rest}
        />
        <button
          :if={@value_string != ""}
          id={"#{@id}-clear"}
          type="button"
          aria-label={"Clear #{@label || "selection"}"}
          tabindex="-1"
          class="absolute inset-y-0 right-2 grid size-6 place-items-center rounded-sm text-ink-muted hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40"
        >
          <.icon name="close" class="size-3.5" />
        </button>
      </div>

      <div
        id={"#{@id}-options"}
        role="listbox"
        aria-label={@label || "Options"}
        tabindex="-1"
        hidden
        class="floating-list z-30 mt-1 max-h-60 min-w-56 overflow-y-auto rounded-xl border border-line bg-surface p-1.5 shadow-lg focus:outline-none"
      >
        <div
          :if={@normalized_options == []}
          id={"#{@id}-empty"}
          class="px-2.5 py-2 text-sm text-ink-muted"
        >
          No options available.
        </div>
        <div
          id={"#{@id}-no-matches"}
          hidden
          class="px-2.5 py-2 text-sm text-ink-muted"
        >
          No matches found.
        </div>
        <div :for={{label, option} <- @normalized_options}>
          <div
            id={"#{@id}-option-#{option}"}
            role="option"
            data-value={option}
            data-label={label}
            aria-selected={if(option == @value_string, do: "true", else: "false")}
            class="cursor-pointer rounded-lg px-2.5 py-1.5 text-sm text-ink hover:bg-surface-sunken"
          >
            {label}
          </div>
        </div>
      </div>

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
  # entirely; the invalid-state styling is not the caller's to replace.
  defp field_class(class, errors, opts \\ []) do
    [
      class || field_base_class(opts[:readonly]),
      is_nil(class) && opts[:extra],
      field_state_class(errors, "border-high-contrast-line")
    ]
  end

  defp normalize_choice_options(options) do
    Enum.map(options || [], fn
      {label, value} ->
        {to_string(label), to_string(value)}

      [label, value] ->
        {to_string(label), to_string(value)}

      %{label: label, value: value} ->
        {to_string(label), to_string(value)}

      value when is_binary(value) or is_atom(value) or is_integer(value) ->
        {to_string(value), to_string(value)}
    end)
  end

  # A field in error reads the same whichever control draws it, so the invalid
  # appearance is decided once here rather than per control family.
  defp field_state_class([], valid_class), do: valid_class

  defp field_state_class(_errors, _valid_class),
    do: "border-danger focus:border-danger focus:ring-danger/20"

  # `readonly` is a statement the caller made about this field. The CSS
  # `:read-only` pseudo-class is not the same statement: it matches every
  # immutable control, including every `select`, `color` and `file` input.
  #
  # Public for `Bilimbi.Base.UI.Components.Lists`, whose toolbar search box is
  # the same field with room for its icon. It is not a caller's styling hook.
  @doc false
  def field_base_class(readonly, padding \\ "px-3") do
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

  The list floats from the trigger (`floating-list` in `app.css`): it is
  placed by the trigger rather than laid out inside the wrapper, so a modal
  dialog, a card or a tile that scrolls or clips cannot cut it off.

  The trigger's `aria-expanded` follows the menu. Clicking the trigger again,
  clicking outside, or moving focus out of the field closes it. While it is
  open, Escape closes it from anywhere on the page; focus returns to the
  trigger only when focus was already inside the field, and otherwise stays
  where the user put it.

  With `chips` the control shows what is chosen instead of counting it: each
  selected option is a chip with a remove button above the trigger, which
  then reads `placeholder` as the verb to add more ("Add roles"). A chip's
  remove button runs `on_remove` with `phx-value-name` (the input name) and
  `phx-value-value` (the option's value), so the owning LiveView drops the
  value from its form and re-renders; the component holds no state of its
  own. The selected options stay checked in the list, so adding and removing
  read as one set either way. This is the chip-and-add shape of the Roles
  control on the user page.

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

  attr(:chips, :boolean,
    default: false,
    doc: "show each selected option as a chip with a remove button; needs `on_remove`"
  )

  attr(:on_remove, JS,
    default: nil,
    doc: "the command a chip's remove button runs, given `phx-value-name` and `phx-value-value`"
  )

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

    # In chip mode the chips carry the selection, so the trigger keeps its
    # verb; a count beside the chips would say the same thing twice.
    summary_label =
      if assigns.chips,
        do: assigns.placeholder,
        else:
          format_selection_summary(selected_count, assigns.placeholder, assigns.selection_label)

    selected_options = Enum.filter(normalized_options, fn {_, val} -> val in selected_values end)

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
    # `DisclosureDismiss` hook, which owns the two dismissals LiveView has
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
      |> assign(:selected_options, selected_options)
      |> assign(:summary_label, summary_label)
      |> assign(:dismiss, dismiss)
      |> assign(:toggle, toggle)
      |> assign(:escape, JS.focus(dismiss, to: "##{id}"))

    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="DisclosureDismiss"
      data-dismiss={@dismiss}
      data-escape={@escape}
      phx-click-away={@dismiss}
      class={["relative floating-scope", @wrapper_class || "mb-4"]}
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

      <div
        :if={@chips and @selected_options != []}
        id={"#{@id}-chips"}
        class="mb-2 flex flex-wrap gap-2"
        role="list"
        aria-labelledby={@label && "#{@id}-label"}
      >
        <span
          :for={{opt_label, opt_value} <- @selected_options}
          id={"#{@id}-chip-#{opt_value}"}
          role="listitem"
          class="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2.5 py-0.5 text-xs font-medium text-ink"
        >
          <span>{opt_label}</span>
          <button
            type="button"
            id={"#{@id}-chip-#{opt_value}-remove"}
            aria-label={gettext("Remove %{option}", option: opt_label)}
            phx-click={@on_remove}
            phx-value-name={@input_name}
            phx-value-value={opt_value}
            class="-mr-1 grid size-5 place-items-center rounded-full text-ink-muted transition hover:bg-surface-sunken hover:text-danger-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong/30"
          >
            <.icon name="close" class="size-3.5" />
          </button>
        </span>
      </div>

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
          "peer group floating-anchor flex w-full items-center justify-between gap-3 rounded-md border bg-surface py-1.5 px-3 text-left text-sm text-ink shadow-xs transition hover:bg-surface-muted focus:outline-none focus:ring-2",
          field_state_class(
            @errors,
            "border-line focus:border-brand-strong focus:ring-brand-strong/30"
          )
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
        class="hidden peer-aria-expanded:block floating-list z-30 mt-1 max-h-60 min-w-56 overflow-y-auto rounded-xl border border-line bg-surface p-1.5 shadow-lg space-y-0.5 focus:outline-none"
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
  attr(:wrapper_class, :any, default: nil)
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
      <legend :if={@label} class="mb-1.5 text-sm font-medium text-ink">
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
            class="size-4 shrink-0 accent-action focus:outline-none focus:ring-2 focus:ring-brand-strong/30 disabled:cursor-not-allowed"
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
