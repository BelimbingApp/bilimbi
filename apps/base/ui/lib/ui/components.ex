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
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed right-4 top-4 z-50 w-[min(24rem,calc(100vw-2rem))]"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-2xl border p-4 text-sm shadow-xl shadow-ink/[0.08] backdrop-blur",
        @kind == :info && "border-success-line bg-success-surface/95 text-success-ink",
        @kind == :error && "border-danger-line bg-danger-surface/95 text-danger-ink"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders an inline status alert (Belimbing's `x-ui.alert` counterpart).

  Kinds map to the honest status roles: `:info`, `:success`, `:warning`,
  `:error`.

  ## Examples

      <.alert kind={:warning}>Your session expired. Sign in again to continue.</.alert>
  """
  attr :kind, :atom, values: [:info, :success, :warning, :error], default: :info
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

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
      <.icon
        name={
          case @kind do
            :info -> "hero-information-circle"
            :success -> "hero-check-circle"
            :warning -> "hero-exclamation-triangle"
            :error -> "hero-exclamation-circle"
          end
        }
        class="mt-0.5 size-4 shrink-0"
      />
      <div class="min-w-0">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc """
  Renders a compact status badge with a state dot, for entity statuses such
  as `"active"` or `"archived"`. Neutral by default; pass `kind` for a
  status color.
  """
  attr :kind, :atom, values: [:neutral, :success, :warning, :danger], default: :neutral
  attr :class, :any, default: nil
  slot :inner_block, required: true

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
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)

  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "bg-action text-action-ink hover:bg-action-hover",
      nil => "border border-line-strong bg-surface text-ink hover:bg-surface-sunken"
    }

    # A caller-supplied class extends the button; it must not replace the
    # variant, or `<.button variant="primary" class="w-full">` silently
    # renders an unstyled button.
    assigns =
      assign(assigns, :class, [
        "inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold",
        "shadow-sm transition focus-visible:outline-none focus-visible:ring-2",
        "focus-visible:ring-action/25 focus-visible:ring-offset-2 focus-visible:ring-offset-canvas",
        "disabled:cursor-not-allowed disabled:opacity-50",
        Map.fetch!(variants, assigns[:variant]),
        assigns[:class]
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
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
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

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
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select multi_select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :size, :integer,
    default: nil,
    doc: "visible rows for a `multiple` select; defaults to 5 so no row is half-painted"

  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :hint, :string,
    default: nil,
    doc: """
    helper text rendered inside the field wrapper, below the control.

    Placing it here rather than in a sibling `<p>` is the point: a paragraph
    after `<.input>` sits outside the wrapper that owns `mb-4`, so callers were
    compensating with four different spacings -- `mt-1`, `mt-1 mb-4`, `mt-0.5`
    and even `-mt-2 mb-4` (#279).
    """

  attr :wrapper_class, :any, default: nil, doc: "the class for the control wrapper"
  attr :label_class, :any, default: nil, doc: "the class for the control label"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

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
              "size-4 shrink-0 rounded border-line-strong accent-action focus:outline-none focus:ring-2 focus:ring-action/20"
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
        "border-line-strong"
      else
        error_class || "border-danger focus:border-danger focus:ring-danger/20"
      end
    ]
  end

  defp field_base_class do
    "block w-full rounded-lg border bg-surface px-3 py-2 text-sm text-ink shadow-xs " <>
      "transition placeholder:text-ink-faint focus:border-action focus:outline-none " <>
      "focus:ring-2 focus:ring-action/20 disabled:cursor-not-allowed " <>
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
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :label, :string, default: nil
  attr :label_class, :any, default: nil
  attr :wrapper_class, :any, default: nil
  attr :class, :any, default: nil

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example @form[:role_ids]"

  attr :errors, :list, default: []

  attr :options, :list,
    default: [],
    doc: "the options to display, list of {label, value} tuples, maps, or strings"

  attr :value, :any, default: nil, doc: "the selected values (if not using field)"
  attr :placeholder, :string, default: "All options", doc: "label when 0 items selected"

  attr :selection_label, :string,
    default: ":count option selected|:count options selected",
    doc: "singular|plural template string for selection count"

  attr :hint, :string, default: nil
  attr :rest, :global, doc: "arbitrary HTML attributes for the button"

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
          "flex w-full items-center justify-between gap-3 rounded-lg border border-line bg-surface py-1.5 px-3 text-left text-sm text-ink shadow-xs transition hover:bg-surface-subtle focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20",
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
            class="size-4 shrink-0 rounded border-line text-action accent-action focus:ring-2 focus:ring-action/20"
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
  Renders pagination controls matching Belimbing design parity.

  Follows Belimbing's `resources/core/views/components/ui/pagination.blade.php`:
  the nav renders when `$hasPages || $hasSelector`, the summary is gated on
  `$summary && $hasPages`, and the page links are gated on `$hasPages` alone.
  """
  attr :id, :string, required: true
  attr :page, :any, required: true
  attr :page_sizes, :list, default: [25, 50, 100, 300]
  attr :filters_form, :any, required: true

  def pagination(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Pagination"
      class="flex flex-col gap-2 border-t border-line-subtle px-2 py-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <p :if={@page.total_pages > 0} id={"#{@id}-summary"} class="text-xs text-ink-muted">
          {page_summary(@page)}
        </p>
        <.form
          id={"#{@id}-page-size-form"}
          for={@filters_form}
          phx-change="filters"
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
        :if={@page.total_pages > 0}
        class="flex items-center gap-1"
        role="list"
        aria-label="Page navigation"
      >
        <button
          id={"#{@id}-previous"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page - 1}
          disabled={@page.page <= 1}
          aria-label="Previous page"
          title="Previous page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <.icon name="hero-chevron-left" class="size-3.5" />
        </button>
        <%= for step <- pagination_steps(@page) do %>
          <span :if={step == :ellipsis} class="px-1 text-xs text-ink-subtle" aria-hidden="true">…</span>
          <button
            :if={is_integer(step)}
            id={"#{@id}-page-#{step}"}
            type="button"
            phx-click="page"
            phx-value-page={step}
            aria-current={if(step == @page.page, do: "page")}
            aria-label={"Page #{step}"}
            class={[
              "grid size-7 place-items-center rounded-md border text-xs tabular-nums transition focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
              step == @page.page && "border-brand-line bg-brand-surface text-brand-ink",
              step != @page.page && "border-line bg-surface text-ink hover:bg-surface-sunken"
            ]}
          >
            {step}
          </button>
        <% end %>
        <button
          id={"#{@id}-next"}
          type="button"
          phx-click="page"
          phx-value-page={@page.page + 1}
          disabled={@page.page >= @page.total_pages or @page.total_pages == 0}
          aria-label="Next page"
          title="Next page"
          class="grid size-7 place-items-center rounded-md border border-line bg-surface text-ink transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <.icon name="hero-chevron-right" class="size-3.5" />
        </button>
      </div>
    </nav>
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
  Renders a timestamp with a readable UTC fallback and browser-local rendering.

  Compatible source timestamps are stored as UTC `NaiveDateTime` values. The
  server-rendered text makes that assumption explicit so the value remains
  truthful before LiveView's JavaScript hook localizes it for the operator.
  """
  attr :id, :string, required: true
  attr :value, :any, default: nil
  attr :format, :atom, values: [:date, :time, :datetime], default: :datetime
  attr :class, :any, default: nil

  def datetime(assigns) do
    assigns = assign(assigns, :date_time, datetime_value(assigns.value))

    ~H"""
    <time
      :if={@date_time}
      id={@id}
      datetime={DateTime.to_iso8601(@date_time)}
      data-format={@format}
      phx-hook="DateTime"
      phx-update="ignore"
      class={["tabular-nums", @class]}
    >
      {server_datetime(@date_time, @format)}
    </time>
    <span :if={is_nil(@date_time)} id={@id} class={@class}>—</span>
    """
  end

  defp datetime_value(%DateTime{} = value), do: value
  defp datetime_value(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp datetime_value(_value), do: nil

  defp server_datetime(value, :date), do: Calendar.strftime(value, "%d/%m/%Y UTC")
  defp server_datetime(value, :time), do: Calendar.strftime(value, "%H:%M UTC")
  defp server_datetime(value, :datetime), do: Calendar.strftime(value, "%d/%m/%Y, %H:%M UTC")

  # Helper used by inputs to generate form errors
  slot :inner_block, required: true

  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-sm text-danger-ink">
      <.icon name="hero-exclamation-circle" class="size-4 shrink-0 text-danger" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a card container with subtle border and rounded corners (Belimbing's `x-ui.card` counterpart).
  """
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :inner_class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

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
  attr :id, :string, default: nil
  attr :variant, :atom, default: :list, values: [:list, :form, :detail]
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

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
  slot :inner_block, required: true
  slot :subtitle
  slot :title_actions
  slot :actions

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
  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  attr :sort_by, :any, default: nil, doc: "active sort key; compared to each column's `sort`"
  attr :sort_dir, :any, default: nil, doc: "`\"asc\"`/`\"desc\"` or `:asc`/`:desc`"

  attr :sort_event, :string,
    default: "sort",
    doc: "the event name pushed when a column sort button is clicked"

  attr :framed, :boolean,
    default: true,
    doc: "when false, omit the outer card chrome so the table can sit in an existing panel"

  attr :caption, :string,
    default: nil,
    doc: "sr-only caption that names the table for assistive tech"

  slot :col, required: true do
    attr :label, :string
    attr :sort, :string, doc: "sort key pushed as phx-value-sort"
    attr :sort_id, :string, doc: "DOM id for the sort button"
    attr :align, :atom, values: [:right], doc: "right-align header and cells (numeric columns)"
  end

  slot :action, doc: "the slot for showing user actions in the last table column"
  slot :empty, doc: "row shown in a sibling tbody when the caller decides the table is empty"

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
          class="divide-y divide-line-subtle"
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
              <div class="flex gap-4">
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
  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :id_value, :any, default: nil
  attr :save_event, :string, default: "save"
  attr :name, :string, default: "value"
  attr :label, :string, default: "Edit value"
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil
  attr :rest, :global

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
          name="hero-pencil"
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

  attr :col, :map, required: true
  attr :table_id, :string, required: true
  attr :sort_by, :any, required: true
  attr :sort_dir, :any, required: true
  attr :sort_event, :string, default: "sort"

  defp table_sort_heading(assigns) do
    ~H"""
    <button
      id={@col[:sort_id] || "#{@table_id}-sort-#{@col[:sort]}"}
      type="button"
      phx-click={@sort_event}
      phx-value-sort={@col[:sort]}
      class={[
        "inline-flex items-center gap-1 rounded transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25",
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
      not table_sort_active?(sort, sort_by) -> "hero-chevron-up-down"
      table_sort_dir(sort_dir) == :asc -> "hero-chevron-up"
      table_sort_dir(sort_dir) == :desc -> "hero-chevron-down"
      true -> "hero-chevron-up-down"
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
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-line-subtle text-sm">
      <div :for={item <- @item} class="flex items-baseline justify-between gap-6 py-2.5">
        <dt class="font-medium text-ink-subtle">{item.title}</dt>
        <dd class="text-right text-ink">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(assigns) do
    case IconRegistry.fetch(assigns.name) do
      {:ok, icon} -> registered_icon(assign(assigns, :icon, icon))
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
