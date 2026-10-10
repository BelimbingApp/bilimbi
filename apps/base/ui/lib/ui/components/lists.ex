defmodule Bilimbi.Base.UI.Components.Lists do
  @moduledoc """
  The operational-list surface: `filter_toolbar/1`, `pagination/1`, `table/1`
  with its `empty_state/1`, `list/1` and `record_link/1`.

  `use Bilimbi.Base.UI.Components` imports it with the rest.
  """
  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Bilimbi.Base.UI.Components.Forms, only: [input: 1, multi_select: 1]
  import Bilimbi.Base.UI.Components.Icon
  import Bilimbi.Base.UI.Components.SortHeading

  alias Bilimbi.Base.UI.Components.Forms

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
        <p
          :if={@page.total_pages > 0}
          id={"#{@id}-summary"}
          class="text-xs tabular-nums text-ink-muted"
        >
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
  Renders the shared list filter toolbar: search fields, selects,
  multi-selects, and date inputs framed as one open toolbar above the list
  surface (Design Spec C04).

  Controls are declared through one repeating `control` slot, at least one of
  them, and render in the order they are written, so the template reads the
  way the toolbar looks.

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
    * Helper text sits below its control in one shape. A select's, a
      multi-select's, and a date's rides its own field component; a search
      box's sits below the box the magnifier is centred in, so helper text
      never stretches that box and drags the magnifier off the input.
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

  # Required: a toolbar with no control is an empty form no list builds.
  slot :control,
    required: true,
    doc: "one filter control per entry, rendered in the order declared" do
    attr(:type, :atom,
      values: [:search, :select, :multi_select, :date],
      required: true,
      doc: "which control to render"
    )

    attr(:field, :any, required: true, doc: "the control's form field")
    attr(:id, :string, required: true, doc: "the control's DOM id")
    attr(:label, :string, required: true, doc: "the control's screen-reader-only label")

    attr(:options, :list, doc: "options passed to the select or multi-select control")

    attr(:placeholder, :string, doc: "`:search` prompt text")
    attr(:selection_label, :string, doc: "`:multi_select` singular|plural summary")
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
          class={Forms.field_base_class(false, "pl-8 pr-3")}
        />
      </div>
      <p :if={@control[:hint]} class="mt-1.5 text-xs text-ink-subtle">{@control[:hint]}</p>
    </div>
    """
  end

  defp toolbar_control(%{control: %{type: :multi_select}} = assigns) do
    ~H"""
    <div class="w-full min-w-0 sm:w-auto sm:min-w-36">
      <.multi_select
        field={@control[:field]}
        id={@control[:id]}
        label={@control[:label]}
        label_class="sr-only"
        wrapper_class="mb-0"
        options={@control[:options]}
        placeholder={@control[:placeholder]}
        selection_label={@control[:selection_label]}
        hint={@control[:hint]}
      />
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

  # Flat on purpose. This component takes no radius, so a rounded table is
  # hand-written markup. DESIGN.md "Table geometry".
  #
  # A row is not clickable. The row that opens a record carries a
  # `<.record_link>` in a cell, which is a real link a keyboard reaches.
  #
  # `data-table-region` marks the scroll box. On a page of its own it only
  # scrolls sideways. Inside a workspace tile the "list fill" rules in
  # `apps/web/assets/css/app.css` give it the room the tile has left, so it
  # scrolls its rows and keeps the heading row stuck to its top.
  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div
      data-table-region
      class={["overflow-x-auto", @framed && "border border-line bg-surface"]}
    >
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
              class={["px-2 py-0.5 text-ink", col[:align] == :right && "text-right"]}
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

  # Say why a region is empty and what to do next. `forbidden` names a
  # permission the actor lacks; it is a different sentence from an empty
  # list. Hiding the control and saying nothing is the mistake.
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
  Renders the link from a list row to a record's page, and inside a tiled
  workspace a button that selects the record instead.

  The selection is answered by the hook `Bilimbi.Base.UI.Workspace.on_mount/4`
  attaches, so the page declares no handler: when another tile follows that
  kind of record, the hook announces the selection on the workspace channel
  and the following tile opens the record while the list stays where it is,
  which is the point of two tiles; when nothing follows it, the hook
  navigates to the record's page as the link would have. Outside a workspace
  (`workspace={nil}`) this is `<.link navigate>` and nothing else, so one
  template serves the page alone and in a tile. Rows are usually streamed
  and re-render only when re-streamed, which is why the decision is made
  when the row is clicked rather than when it is rendered.

  `kind` is the stable module id that owns the record, `"core/company"`,
  and `record_id` its record id. Pass the page's `@workspace` assign.

  ## Examples

      <.record_link
        workspace={@workspace}
        kind="core/company"
        record_id={company.id}
        navigate={~p"/companies/\#{company.id}"}
        class="font-medium text-ink-strong hover:underline"
      >
        {company.name}
      </.record_link>
  """
  attr(:workspace, :any, required: true, doc: "the page's `@workspace` assign; `nil` alone")
  attr(:kind, :string, required: true, doc: "the module id that owns the record")
  attr(:record_id, :any, required: true, doc: "the record's id")
  attr(:navigate, :string, required: true, doc: "the record's own page")
  attr(:class, :any, default: nil)
  attr(:rest, :global, include: ~w(title))
  slot(:inner_block, required: true)

  def record_link(assigns) do
    if assigns.workspace do
      ~H"""
      <button
        type="button"
        phx-click="workspace:select"
        phx-value-kind={@kind}
        phx-value-id={@record_id}
        phx-value-path={@navigate}
        data-record-select
        class={[@class, "text-left"]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
      """
    else
      ~H"""
      <.link navigate={@navigate} class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    end
  end
end
