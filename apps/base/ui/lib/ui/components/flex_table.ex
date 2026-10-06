defmodule Bilimbi.Base.UI.Components.FlexTable do
  @moduledoc """
  The flexible table: `flex_table/1`, whose columns a person adds, removes,
  reorders and reads through a lens, in normal or compact rows. Its data
  shapes are `Bilimbi.Base.UI.FlexTable`.

  `use Bilimbi.Base.UI.Components` imports it with the rest. It is the top
  group: it imports `Bilimbi.Base.UI.Components` and the Lists group, and no
  group imports it.
  """
  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Bilimbi.Base.UI.Components, only: [datetime: 1, icon_button: 1]
  import Bilimbi.Base.UI.Components.Icon
  import Bilimbi.Base.UI.Components.Lists, only: [empty_state: 1]
  import Bilimbi.Base.UI.Components.SortHeading

  alias Phoenix.LiveView.JS

  @doc """
  Renders a flexible table: columns a person adds by walking links, removes,
  reorders by drag, and reads through a lens; rollup cells that expand in
  place; and rows that are normal or compact.

  The component is presentation only. It takes the plain columns and
  prepared cells described in `Bilimbi.Base.UI.FlexTable` and pushes one
  event, `event`, with an `op`, to the host that owns the data. It is a
  table with the density of `table/1`, and a `:slot` column is drawn by the
  caller's `<:col>` of the same id, so a list page keeps its own links and
  badges while gaining walked columns beside them.

  There is no toolbar. Two icon buttons sit in the corner of the table's
  header: the density toggle, and a settings icon that opens table
  customization, the panel holding a chip per column (drag to reorder,
  remove, choose a lens), the add-a-column box and, while a change-since
  lens is worn, its date. The panel is closed until asked for and closes
  on a click outside it or Escape.

  `mode` is `:normal` or `:compact`, the host's decision and what the
  density toggle switches. Compact is the same table with tighter rows that
  do not wrap, so more rows and more columns fit a screen and the table
  scrolls sideways; every link, sort and rollup works in both. A caller
  that draws a second line in a `<:col>` leaves it out in compact.

  Bars and bands: a `:band` cell carries `data-band` and `data-scale` and is
  painted by `app.css`; a `:bar` cell carries `data-bar` and the hook writes
  its width, because the CSP refuses an inline style.

  ## Examples

      <.flex_table
        id="users"
        columns={@columns.column_views}
        rows={@columns.rows}
        mode={@columns.mode}
        sort_by={@index_state.sort_by}
        sort_dir={@index_state.sort_dir}
        suggestions={@columns.suggestions}
        add_query={@columns.add_query}
      >
        <:col id="name" :let={row}><.link navigate={...}>...</.link></:col>
        <:action :let={row}>...</:action>
        <:empty title="No users match" reason="Clear the search." />
      </.flex_table>
  """
  attr(:id, :string, required: true)

  attr(:columns, :list,
    required: true,
    doc: "ordered column maps; see `Bilimbi.Base.UI.FlexTable`"
  )

  attr(:rows, :list, required: true, doc: "`%{key, cells}` maps, in the order shown")

  attr(:mode, :atom,
    values: [:normal, :compact],
    default: :normal,
    doc: "`:compact` tightens the rows and keeps each on one line"
  )

  attr(:event, :string,
    default: "grid",
    doc: "the one event every operation pushes, with an `op`"
  )

  attr(:target, :any, default: nil, doc: "`phx-target` for the event; a LiveView passes nothing")
  attr(:sort_by, :any, default: nil, doc: "the spec of the sorted column, as `table/1` takes it")
  attr(:sort_dir, :any, default: nil, doc: "`\"asc\"`/`\"desc\"` or `:asc`/`:desc`")

  attr(:suggestions, :list,
    default: [],
    doc: "column maps the add-a-column box offers for what was typed"
  )

  attr(:add_query, :string, default: "", doc: "what is typed in the add-a-column box")

  attr(:cost, :any,
    default: nil,
    doc:
      "`%{estimate: float, heavy?: boolean}`, the planner's estimate for the statement " <>
        "that scales bars and colour bands over the whole table, or nil"
  )

  attr(:since, :any,
    default: nil,
    doc: "the `Date` a change-since lens compares against; the control shows when one is worn"
  )

  attr(:expanded, :map,
    default: %{},
    doc: "`%{key => %{column_id => [row maps]}}` rollups opened in place"
  )

  attr(:caption, :string, default: nil, doc: "sr-only caption naming the table")

  attr(:row_id, :any,
    default: nil,
    doc: "a function from a row key to the row's DOM id; defaults to `<id>-row-<key>`"
  )

  slot :col, doc: "draws a `:slot` column; matched to the column by `id`" do
    attr(:id, :string, required: true)
  end

  slot(:action, doc: "row actions in the last column")

  slot :empty, doc: "what to say when there are no rows, as `table/1` takes it" do
    attr(:title, :string)
    attr(:reason, :string)
    attr(:forbidden, :string)
  end

  def flex_table(assigns) do
    assigns =
      assigns
      |> assign(:slots_by_id, Map.new(assigns.col, &{&1.id, &1}))
      |> assign(:compact?, assigns.mode == :compact)
      |> assign(:delta?, Enum.any?(assigns.columns, &(Map.get(&1, :lens) == :delta)))
      |> assign_customization()
      |> assign_new(:row_dom_id, fn %{id: id, row_id: row_id} ->
        row_id || fn key -> "#{id}-row-#{Bilimbi.Base.UI.FlexTable.key_id(key)}" end
      end)

    ~H"""
    <div
      id={@id}
      phx-hook="FlexTable"
      data-event={@event}
      data-target={@target}
      data-mode={@mode}
      class="flex-table"
    >
      <p
        :if={@cost && @cost.heavy?}
        id={"#{@id}-cost"}
        class="mb-2 flex items-center gap-1 text-xs text-warning-ink"
      >
        <.icon name="warning" class="size-3.5" />
        {gettext(
          "Heavy query: scaling these bars and colour bands reads the whole table, and the planner estimates a cost of %{cost}. Fewer rollups under a bar or band lens would lighten it.",
          cost: trunc(@cost.estimate)
        )}
      </p>
      <div class="relative">
        <%!-- The table's two controls sit in the corner of its header and
             stay there when the table scrolls sideways. The density toggle
             is always in reach; table customization is a panel that opens
             from the settings icon, closed until asked for. `aria-expanded`
             on that icon is the one record of open, as on `multi_select/1`,
             and the panel leaves the scrolling table through
             `floating-panel` so nothing clips it. It stays open while its
             chips and suggestions come and go, and closes on a click
             outside it or Escape, which returns focus to the icon. --%>
        <div
          id={"#{@id}-controls"}
          phx-hook="DisclosureDismiss"
          data-dismiss={@close}
          data-escape={@escape}
          data-keep-on-blur
          phx-click-away={@close}
          class={[
            "floating-scope absolute right-px top-px z-10 flex items-center gap-0.5 bg-surface-sunken px-1",
            if(@compact?, do: "h-6", else: "h-8")
          ]}
        >
          <%!-- One toggle, two densities. The name stays "Compact rows" and
               `aria-pressed` says whether it is on; the tooltip names the
               density the press switches to. --%>
          <.icon_button
            icon="compact"
            context={:inline}
            id={"#{@id}-density"}
            label={gettext("Compact rows")}
            title={
              if @compact?,
                do: gettext("Compact rows are on. Switch to normal rows."),
                else: gettext("Normal rows are on. Switch to compact rows.")
            }
            aria-pressed={to_string(@compact?)}
            phx-click={@event}
            phx-target={@target}
            phx-value-op="density"
            phx-value-density={if @compact?, do: "normal", else: "compact"}
            class="aria-pressed:bg-brand-surface aria-pressed:text-brand-ink"
          />
          <.icon_button
            icon="settings"
            context={:inline}
            id={"#{@id}-customize"}
            label={gettext("Customize table")}
            aria-expanded="false"
            aria-controls={"#{@id}-customization"}
            phx-click={@toggle}
            class="peer floating-anchor aria-expanded:bg-brand-surface aria-expanded:text-brand-ink"
          />
          <div
            id={"#{@id}-customization"}
            role="group"
            aria-label={gettext("Table customization")}
            class="floating-panel z-30 mt-1 hidden max-h-[min(32rem,calc(100dvh-6rem))] w-80 max-w-[calc(100vw-1.5rem)] space-y-3 overflow-y-auto rounded-xl border border-line bg-surface p-3 text-left shadow-lg peer-aria-expanded:block"
          >
            <div>
              <p class="text-sm font-medium text-ink-strong">{gettext("Customize table")}</p>
              <p class="text-xs font-normal text-ink-subtle">
                {gettext(
                  "Drag a column to reorder it. Changes are kept for your account on this page."
                )}
              </p>
            </div>
            <ul
              id={"#{@id}-chips"}
              role="list"
              aria-label={gettext("Columns")}
              class="flex flex-wrap items-center gap-1"
            >
              <li
                :for={column <- @columns}
                id={"#{@id}-chip-#{column.id}"}
                data-chip={column.spec}
                draggable="true"
                title={column.label}
                class="group flex h-6 cursor-grab items-center gap-0.5 rounded-md border border-line bg-surface pl-2 pr-0.5 text-xs font-normal text-ink"
              >
                <span class="max-w-40 truncate">{column.short_label}</span>
                <.flex_table_lens_menu
                  :if={length(Map.get(column, :lenses, [:value])) > 1}
                  table_id={@id}
                  column={column}
                  event={@event}
                  target={@target}
                />
                <.icon_button
                  :if={Map.get(column, :removable, true)}
                  icon="close"
                  context={:inline}
                  label={gettext("Remove column %{name}", name: column.label)}
                  id={"#{@id}-remove-#{column.id}"}
                  phx-click={@event}
                  phx-target={@target}
                  phx-value-op="remove"
                  phx-value-spec={column.spec}
                  class="size-5"
                />
              </li>
            </ul>
            <form
              id={"#{@id}-add-column"}
              phx-change={@event}
              phx-submit={JS.push(@event, value: %{op: "add_typed"})}
              phx-target={@target}
              role="search"
            >
              <input type="hidden" name="op" value="suggest" />
              <label for={"#{@id}-add-column-input"} class="sr-only">{gettext("Add a column")}</label>
              <div class="relative">
                <.icon
                  name="create"
                  class="pointer-events-none absolute left-2 top-1/2 size-3.5 -translate-y-1/2 text-ink-faint"
                />
                <input
                  id={"#{@id}-add-column-input"}
                  name="add"
                  type="search"
                  value={@add_query}
                  placeholder={gettext("Add a column, e.g. company name…")}
                  autocomplete="off"
                  phx-debounce="200"
                  role="combobox"
                  aria-expanded={to_string(@suggestions != [])}
                  aria-controls={"#{@id}-suggestions"}
                  aria-autocomplete="list"
                  class="h-7 w-full rounded-md border border-line bg-surface pl-7 pr-2 text-xs font-normal text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30"
                />
              </div>
              <%!-- The suggestions are part of the panel, not a list floating
                   over it: the panel is already the thing that floats. --%>
              <ul
                :if={@suggestions != []}
                id={"#{@id}-suggestions"}
                role="listbox"
                class="mt-1 rounded-md border border-line bg-surface p-1"
              >
                <li :for={suggestion <- @suggestions} role="option" aria-selected="false">
                  <button
                    type="button"
                    id={"#{@id}-suggest-#{suggestion.id}"}
                    phx-click={@event}
                    phx-target={@target}
                    phx-value-op="add"
                    phx-value-spec={suggestion.spec}
                    class="flex w-full items-baseline justify-between gap-2 rounded-sm px-2 py-1 text-left text-xs font-normal text-ink hover:bg-surface-muted focus-visible:bg-surface-muted focus-visible:outline-none"
                  >
                    <span class="truncate">{suggestion.label}</span>
                    <span class="shrink-0 font-mono text-[0.65rem] text-ink-faint">{suggestion.spec}</span>
                  </button>
                </li>
              </ul>
            </form>
            <form
              :if={@delta?}
              id={"#{@id}-since"}
              phx-change={JS.push(@event, value: %{op: "since"})}
              phx-submit={JS.push(@event, value: %{op: "since"})}
              phx-target={@target}
              class="flex items-center gap-1.5 text-xs font-normal text-ink-muted"
            >
              <label for={"#{@id}-since-input"}>{gettext("Change since")}</label>
              <input
                id={"#{@id}-since-input"}
                name="since"
                type="date"
                value={@since && Date.to_iso8601(@since)}
                required
                class="h-7 rounded-md border border-line bg-surface px-1.5 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30"
              />
            </form>
          </div>
        </div>
        <div
          id={"#{@id}-viewport"}
          data-viewport
          class="relative overflow-auto border border-line bg-surface"
          tabindex="0"
        >
          <table class={["w-full text-left", if(@compact?, do: "text-xs", else: "text-sm")]}>
            <caption :if={@caption} class="sr-only">{@caption}</caption>
            <thead class="border-b border-line bg-surface-sunken">
              <tr>
                <th
                  :for={column <- @columns}
                  id={"#{@id}-head-#{column.id}"}
                  scope="col"
                  draggable="true"
                  data-header={column.spec}
                  aria-sort={table_aria_sort(column.spec, @sort_by, @sort_dir)}
                  title={column.label}
                  class={[
                    "cursor-grab text-xs font-semibold text-ink-subtle",
                    if(@compact?, do: "whitespace-nowrap px-1.5 py-1", else: "px-2 py-1.5"),
                    Map.get(column, :align) == :right && "text-right"
                  ]}
                >
                  <.table_sort_heading
                    :if={Map.get(column, :sortable, true)}
                    col={
                      %{
                        sort: column.spec,
                        sort_id: Map.get(column, :sort_id) || "#{@id}-sort-#{column.id}",
                        label: column.short_label,
                        align: Map.get(column, :align)
                      }
                    }
                    table_id={@id}
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                    sort_event={JS.push(@event, value: %{op: "sort"})}
                    sort_target={@target}
                  />
                  <span :if={!Map.get(column, :sortable, true)}>{column.short_label}</span>
                </th>
                <%!-- The last heading keeps room for the two controls that sit
                   over this corner, whether or not the rows carry actions. --%>
                <th scope="col" class="w-16 min-w-16">
                  <span :if={@action != []} class="sr-only">{gettext("Actions")}</span>
                </th>
              </tr>
            </thead>
            <tbody id={"#{@id}-rows"} class="divide-y divide-low-contrast-line">
              <%= for row <- @rows do %>
                <tr id={@row_dom_id.(row.key)} class="hover:bg-surface-sunken">
                  <.flex_table_cell
                    :for={column <- @columns}
                    table_id={@id}
                    column={column}
                    row={row}
                    cell={Map.get(row.cells, column.id)}
                    slot={Map.get(@slots_by_id, column.id)}
                    compact={@compact?}
                    expanded={@expanded |> Map.get(row.key, %{}) |> Map.has_key?(column.id)}
                    event={@event}
                    target={@target}
                  />
                  <%!-- A compact row is shorter than a table icon button, so
                     the row's own controls take the inline size there. --%>
                  <td
                    :if={@action != []}
                    class={[
                      "w-0 font-semibold",
                      if(@compact?,
                        do: "px-1.5 py-0 [&_a]:size-5 [&_button]:size-5",
                        else: "px-2 py-0.5"
                      )
                    ]}
                  >
                    <div class="flex items-center justify-end gap-1">
                      <%= for action <- @action do %>
                        {render_slot(action, row)}
                      <% end %>
                    </div>
                  </td>
                  <td :if={@action == []}></td>
                </tr>
                <tr
                  :for={{column_id, opened} <- Map.get(@expanded, row.key, %{})}
                  id={"#{@row_dom_id.(row.key)}-#{column_id}"}
                  class="bg-surface-muted"
                >
                  <td
                    colspan={length(@columns) + 1}
                    class="px-6 py-1.5"
                  >
                    <.flex_table_expansion rows={opened} />
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tbody :if={@empty != [] and @rows == []}>
              <tr id={"#{@id}-empty"}>
                <td
                  colspan={length(@columns) + 1}
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
      </div>
    </div>
    """
  end

  # The commands that open and close table customization. Each writes only
  # the settings icon's `aria-expanded`; the panel's visibility is CSS
  # derived from it, so a patch that redraws the chips leaves it open.
  defp assign_customization(%{id: id} = assigns) do
    close = JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-customize")

    assigns
    |> assign(:close, close)
    |> assign(:escape, JS.focus(close, to: "##{id}-customize"))
    |> assign(
      :toggle,
      JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-customize")
    )
  end

  attr(:table_id, :string, required: true)
  attr(:column, :map, required: true)
  attr(:row, :map, required: true)
  attr(:cell, :any, default: nil)
  attr(:slot, :any, default: nil)
  attr(:compact, :boolean, default: false)
  attr(:expanded, :boolean, default: false)
  attr(:event, :string, required: true)
  attr(:target, :any, default: nil)

  # One cell. A slot column defers to the caller; a rollup is a button that
  # opens the rows it collapsed beneath the row; a bar or a band carries the
  # data attributes the stylesheet and the hook paint from.
  defp flex_table_cell(%{slot: slot} = assigns) when not is_nil(slot) do
    assigns = assign(assigns, :cell_id, flex_table_cell_id(assigns))

    ~H"""
    <td
      id={@cell_id}
      class={[
        "text-ink",
        cell_density(@compact),
        Map.get(@column, :align) == :right && "text-right"
      ]}
    >
      {render_slot(@slot, @row)}
    </td>
    """
  end

  defp flex_table_cell(%{column: %{kind: :rollup}} = assigns) do
    assigns = assign(assigns, :cell_id, flex_table_cell_id(assigns))

    ~H"""
    <td
      id={@cell_id}
      class={["text-ink tabular-nums", cell_density(@compact)]}
      data-band={band_attr(@column, @cell)}
      data-scale={scale_attr(@column, @cell)}
    >
      <button
        type="button"
        id={"#{@table_id}-expand-#{Bilimbi.Base.UI.FlexTable.key_id(@row.key)}-#{@column.id}"}
        phx-click={@event}
        phx-target={@target}
        phx-value-op={if @expanded, do: "collapse", else: "expand"}
        phx-value-spec={@column.spec}
        phx-value-key={@row.key}
        aria-expanded={to_string(@expanded)}
        class="inline-flex max-w-full items-center gap-1 rounded-sm text-left hover:text-ink-strong hover:underline focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40"
      >
        <.icon
          name={if @expanded, do: "collapse", else: "expand"}
          class="size-3 shrink-0 text-ink-faint"
        />
        <.flex_table_value id={"#{@cell_id}-value"} column={@column} cell={@cell} />
      </button>
    </td>
    """
  end

  defp flex_table_cell(assigns) do
    assigns = assign(assigns, :cell_id, flex_table_cell_id(assigns))

    ~H"""
    <td
      id={@cell_id}
      class={[
        "text-ink",
        cell_density(@compact),
        Map.get(@column, :align) == :right && "text-right",
        @column.type in [:integer, :float, :decimal, :date, :datetime] && "tabular-nums"
      ]}
      data-band={band_attr(@column, @cell)}
      data-scale={scale_attr(@column, @cell)}
    >
      <.flex_table_value id={"#{@cell_id}-value"} column={@column} cell={@cell} />
    </td>
    """
  end

  # A compact row is one line however long its text is.
  defp cell_density(true), do: "whitespace-nowrap px-1.5 py-0 leading-5"
  defp cell_density(false), do: "px-2 py-0.5"

  defp flex_table_cell_id(%{table_id: table_id, row: row, column: column}) do
    "#{table_id}-cell-#{Bilimbi.Base.UI.FlexTable.key_id(row.key)}-#{column.id}"
  end

  attr(:id, :string, required: true)
  attr(:column, :map, required: true)
  attr(:cell, :any, default: nil)

  defp flex_table_value(%{cell: nil} = assigns) do
    ~H"""
    <span class="text-ink-faint">—</span>
    """
  end

  defp flex_table_value(%{column: %{lens: :bar}} = assigns) do
    ~H"""
    <span class="flex items-center gap-2">
      <span
        class="relative h-2 w-20 shrink-0 overflow-hidden rounded-sm bg-surface-sunken"
        aria-hidden="true"
      >
        <span class="absolute inset-y-0 left-0" data-bar={Bilimbi.Base.UI.FlexTable.bar_width(@cell)}></span>
      </span>
      <span class="truncate">{@cell.text}</span>
    </span>
    """
  end

  defp flex_table_value(%{column: %{lens: :trend}, cell: %{series: series}} = assigns)
       when is_list(series) do
    assigns = assign(assigns, :points, Bilimbi.Base.UI.FlexTable.sparkline(series))

    ~H"""
    <span class="flex items-center gap-2">
      <svg
        :if={@points}
        viewBox="0 0 60 16"
        width="60"
        height="16"
        class="shrink-0 text-scale-4"
        aria-hidden="true"
      >
        <polyline points={@points} fill="none" stroke="currentColor" stroke-width="1.5" />
      </svg>
      <span class="truncate">{@cell.text}</span>
    </span>
    """
  end

  defp flex_table_value(%{column: %{type: type}, cell: %{value: %NaiveDateTime{}}} = assigns)
       when type == :datetime do
    ~H"""
    <.datetime id={@id} value={@cell.value} />
    """
  end

  defp flex_table_value(%{cell: %{text: ""}} = assigns) do
    ~H"""
    <span class="text-ink-faint">—</span>
    """
  end

  defp flex_table_value(assigns) do
    ~H"""
    <span class="truncate">{@cell.text}</span>
    """
  end

  defp band_attr(%{lens: :band}, %{band: band}) when is_integer(band), do: band
  defp band_attr(_column, _cell), do: nil

  defp scale_attr(%{lens: :band}, %{scale: scale, band: band})
       when is_integer(band) and not is_nil(scale), do: scale

  defp scale_attr(_column, _cell), do: nil

  attr(:table_id, :string, required: true)
  attr(:column, :map, required: true)
  attr(:event, :string, required: true)
  attr(:target, :any, default: nil)

  # The lens switch on a chip: a disclosure of the lenses the column allows,
  # closed by `DisclosureDismiss` on Escape or when focus leaves, like the
  # tile menu.
  defp flex_table_lens_menu(assigns) do
    menu = "#{assigns.table_id}-lens-#{assigns.column.id}"
    dismiss = JS.set_attribute({"aria-expanded", "false"}, to: "##{menu}")

    assigns =
      assigns
      |> assign(:menu, menu)
      |> assign(:dismiss, dismiss)
      |> assign(:escape, JS.focus(dismiss, to: "##{menu}"))
      |> assign(:toggle, JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{menu}"))

    ~H"""
    <span
      id={"#{@menu}-wrap"}
      phx-hook="DisclosureDismiss"
      data-dismiss={@dismiss}
      data-escape={@escape}
      phx-click-away={@dismiss}
      class="floating-scope relative"
    >
      <button
        id={@menu}
        type="button"
        aria-expanded="false"
        aria-controls={"#{@menu}-items"}
        aria-label={
          gettext("Lens for %{name}: %{lens}",
            name: @column.label,
            lens: Bilimbi.Base.UI.FlexTable.lens_label(Map.get(@column, :lens, :value))
          )
        }
        title={
          gettext("Lens: %{lens}",
            lens: Bilimbi.Base.UI.FlexTable.lens_label(Map.get(@column, :lens, :value))
          )
        }
        phx-click={@toggle}
        class="peer floating-anchor grid size-5 place-items-center rounded-sm text-ink-muted transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40"
      >
        <.icon name={lens_icon(Map.get(@column, :lens, :value))} class="size-3" />
      </button>
      <div
        id={"#{@menu}-items"}
        class="floating-list z-40 mt-0.5 hidden min-w-32 rounded-md border border-line bg-surface p-1 shadow-lg peer-aria-expanded:block"
      >
        <button
          :for={lens <- Map.get(@column, :lenses, [:value])}
          type="button"
          id={"#{@menu}-#{lens}"}
          phx-click={
            %JS{
              ops:
                JS.push(@event, value: %{op: "lens", spec: @column.spec, lens: lens}).ops ++
                  @dismiss.ops
            }
          }
          phx-target={@target}
          aria-pressed={to_string(Map.get(@column, :lens, :value) == lens)}
          class={[
            "block w-full rounded-sm px-2 py-1 text-left text-xs hover:bg-surface-muted focus-visible:bg-surface-muted focus-visible:outline-none",
            Map.get(@column, :lens, :value) == lens && "text-brand-strong",
            Map.get(@column, :lens, :value) != lens && "text-ink"
          ]}
        >
          {Bilimbi.Base.UI.FlexTable.lens_label(lens)}
        </button>
      </div>
    </span>
    """
  end

  defp lens_icon(:bar), do: "hero-chart-bar"
  defp lens_icon(:band), do: "hero-paint-brush"
  defp lens_icon(:trend), do: "hero-arrow-trending-up"
  defp lens_icon(:delta), do: "hero-calendar-days"
  defp lens_icon(_lens), do: "hero-bars-3-bottom-left"

  attr(:rows, :list, required: true)

  # The rows a rollup collapsed, shown beneath their parent as a compact
  # inner table whose headings are the target's field ids.
  defp flex_table_expansion(%{rows: []} = assigns) do
    ~H"""
    <p class="text-xs text-ink-muted">{gettext("Nothing linked.")}</p>
    """
  end

  defp flex_table_expansion(assigns) do
    assigns = assign(assigns, :headings, assigns.rows |> hd() |> Map.keys() |> Enum.sort())

    ~H"""
    <table class="w-full text-left text-xs">
      <thead>
        <tr>
          <th :for={heading <- @headings} scope="col" class="px-2 py-1 font-semibold text-ink-subtle">
            {heading |> String.replace("_", " ") |> String.capitalize()}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-low-contrast-line">
        <tr :for={row <- @rows}>
          <td :for={heading <- @headings} class="px-2 py-0.5 text-ink tabular-nums">
            {flex_table_plain(Map.get(row, heading))}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  # The host hands expansion rows as text already; only nil and booleans
  # need a word here.
  defp flex_table_plain(nil), do: "—"
  defp flex_table_plain(true), do: "Yes"
  defp flex_table_plain(false), do: "No"
  defp flex_table_plain(other), do: to_string(other)
end
