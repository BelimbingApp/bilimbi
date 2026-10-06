defmodule Bilimbi.Base.UI.Components.FlexTable do
  @moduledoc """
  The flexible table: `flex_table/1`, whose columns a person adds, removes,
  reorders, reads through a lens and zooms. Its data preparation is
  `Bilimbi.Base.UI.FlexTable`.

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
  place; and a semantic zoom from a full table down to a heat carpet where
  every cell is a coloured square.

  The component is presentation only. It takes the plain columns and
  prepared cells described in `Bilimbi.Base.UI.FlexTable` and pushes one
  event, `event`, with an `op`, to the host that owns the data. In `:full`
  mode it is a table with the density of `table/1`, and a `:slot` column is
  drawn by the caller's `<:col>` of the same id, so a list page keeps its
  own links and badges while gaining walked columns beside them. In `:mid`
  and `:carpet` mode the `FlexTable` hook draws the rows on a canvas from
  windows the host pushes as `"<id>:window"` events, and only the visible
  window is ever sent or drawn.

  The mode is the host's decision (`mode`), derived from the zoom by one
  rule the host owns, so the table cannot disagree with the page about
  where compact ends and carpet begins. The toolbar states the mode in
  words, never by cell size alone.

  Bars and bands: a `:band` cell carries `data-band` and `data-scale` and is
  painted by `app.css`; a `:bar` cell carries `data-bar` and the hook writes
  its width, because the CSP refuses an inline style.

  ## Examples

      <.flex_table
        id="users-grid"
        columns={@columns}
        rows={@rows}
        mode={:full}
        zoom={28}
        sort_by={@view.sort}
        sort_dir={@view.dir}
        suggestions={@suggestions}
        add_query={@add_query}
        total={@total}
      >
        <:col id="name" :let={row}><.link navigate={...}>{row.cells["name"].text}</.link></:col>
        <:action :let={row}>...</:action>
        <:empty title="No users match" reason="Clear the search." />
      </.flex_table>
  """
  attr(:id, :string, required: true)

  attr(:columns, :list,
    required: true,
    doc: "ordered column maps; see `Bilimbi.Base.UI.FlexTable`"
  )

  attr(:rows, :list, required: true, doc: "`%{key, cells}` maps for the window shown")
  attr(:mode, :atom, values: [:carpet, :mid, :full], default: :full)
  attr(:zoom, :integer, default: 28, doc: "the row height in pixels the mode was derived from")

  attr(:event, :string,
    default: "grid",
    doc: "the one event every operation pushes, with an `op`"
  )

  attr(:target, :any, default: nil, doc: "`phx-target` for the event; a LiveView passes nothing")
  attr(:sort_by, :string, default: nil, doc: "the spec of the sorted column")
  attr(:sort_dir, :atom, values: [:asc, :desc], default: :asc)
  attr(:suggestions, :list, default: [], doc: "column maps the add bar offers for what was typed")
  attr(:add_query, :string, default: "", doc: "what is typed in the add bar")
  attr(:total, :integer, default: 0, doc: "how many rows the whole set has")
  attr(:offset, :integer, default: 0, doc: "the index of the first row in `rows`")

  attr(:cost, :any,
    default: nil,
    doc: "`%{estimate: float, heavy?: boolean}` from the planner, or nil"
  )

  attr(:expanded, :map,
    default: %{},
    doc: "`%{key => %{column_id => [row maps]}}` rollups opened in place"
  )

  attr(:group, :string, default: nil, doc: "the spec the rows are grouped by, if any")
  attr(:pivot, :string, default: nil, doc: "the spec whose values are the columns, if pivoted")
  attr(:caption, :string, default: nil, doc: "sr-only caption naming the table")

  attr(:row_id, :any,
    default: nil,
    doc: "a function from a row key to the row's DOM id; defaults to `<id>-row-<key>`"
  )

  slot :col, doc: "draws a `:slot` column in full mode; matched to the column by `id`" do
    attr(:id, :string, required: true)
  end

  slot(:action, doc: "row actions in the last column of the full table")

  slot :empty, doc: "what to say when there are no rows, as `table/1` takes it" do
    attr(:title, :string)
    attr(:reason, :string)
    attr(:forbidden, :string)
  end

  def flex_table(assigns) do
    assigns =
      assigns
      |> assign(:columns_json, Bilimbi.Base.UI.FlexTable.columns_json(assigns.columns))
      |> assign(:canvas?, Bilimbi.Base.UI.FlexTable.canvas?(assigns.mode))
      |> assign(:slots_by_id, Map.new(assigns.col, &{&1.id, &1}))
      |> assign(:mode_label, Bilimbi.Base.UI.FlexTable.mode_label(assigns.mode))
      |> assign(:presets, [{:carpet, 3}, {:mid, 12}, {:full, 28}])
      |> assign_new(:row_dom_id, fn %{id: id, row_id: row_id} ->
        row_id || fn key -> "#{id}-row-#{Bilimbi.Base.UI.FlexTable.key_id(key)}" end
      end)
      |> then(fn assigns ->
        assign(
          assigns,
          :groups,
          Bilimbi.Base.UI.FlexTable.groups(assigns.rows, assigns.columns, assigns.group)
        )
      end)

    ~H"""
    <div
      id={@id}
      phx-hook="FlexTable"
      data-event={@event}
      data-target={@target}
      data-zoom={@zoom}
      data-mode={@mode}
      data-columns={@columns_json}
      data-total={@total}
      data-offset={@offset}
      class="flex-table"
    >
      <div id={"#{@id}-toolbar"} class="mb-2 flex flex-wrap items-center gap-x-3 gap-y-2">
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
            class="group flex h-6 cursor-grab items-center gap-0.5 rounded-md border border-line bg-surface pl-2 pr-0.5 text-xs text-ink"
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
          class="relative min-w-52"
          role="search"
        >
          <input type="hidden" name="op" value="suggest" />
          <label for={"#{@id}-add-column-input"} class="sr-only">{gettext("Add a column")}</label>
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
            class="h-7 w-full rounded-md border border-line bg-surface pl-7 pr-2 text-xs text-ink placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30"
          />
          <ul
            :if={@suggestions != []}
            id={"#{@id}-suggestions"}
            role="listbox"
            class="absolute left-0 top-full z-30 mt-1 max-h-72 w-96 max-w-[90vw] overflow-y-auto rounded-md border border-line bg-surface p-1 shadow-lg"
          >
            <li :for={suggestion <- @suggestions} role="option" aria-selected="false">
              <button
                type="button"
                id={"#{@id}-suggest-#{suggestion.id}"}
                phx-click={@event}
                phx-target={@target}
                phx-value-op="add"
                phx-value-spec={suggestion.spec}
                class="flex w-full items-baseline justify-between gap-2 rounded-sm px-2 py-1 text-left text-xs text-ink hover:bg-surface-muted focus-visible:bg-surface-muted focus-visible:outline-none"
              >
                <span class="truncate">{suggestion.label}</span>
                <span class="shrink-0 font-mono text-[0.65rem] text-ink-faint">{suggestion.spec}</span>
              </button>
            </li>
          </ul>
        </form>
        <div
          id={"#{@id}-zoom"}
          role="group"
          aria-label={gettext("Zoom")}
          class="flex items-center gap-0.5"
        >
          <.icon_button
            icon="zoom-out"
            context={:inline}
            label={gettext("Zoom out")}
            id={"#{@id}-zoom-out"}
            phx-click={@event}
            phx-target={@target}
            phx-value-op="zoom"
            phx-value-dir="out"
          />
          <span
            id={"#{@id}-zoom-level"}
            class="min-w-12 text-center text-xs tabular-nums text-ink-muted"
            title={gettext("%{mode} view, rows %{px} px tall", mode: @mode_label, px: @zoom)}
          >
            {@zoom} px
          </span>
          <.icon_button
            icon="zoom-in"
            context={:inline}
            label={gettext("Zoom in")}
            id={"#{@id}-zoom-in"}
            phx-click={@event}
            phx-target={@target}
            phx-value-op="zoom"
            phx-value-dir="in"
          />
          <button
            :for={{preset, z} <- @presets}
            type="button"
            id={"#{@id}-zoom-#{preset}"}
            phx-click={@event}
            phx-target={@target}
            phx-value-op="zoom_preset"
            phx-value-z={z}
            aria-pressed={to_string(@mode == preset)}
            class={[
              "rounded-md border px-1.5 py-0.5 text-xs transition focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40",
              @mode == preset && "border-selection-line bg-brand-surface text-brand-ink",
              @mode != preset &&
                "border-line bg-surface text-ink-muted hover:bg-surface-sunken hover:text-ink"
            ]}
          >
            {Bilimbi.Base.UI.FlexTable.mode_label(preset)}
          </button>
        </div>
        <p
          :if={@cost && @cost.heavy?}
          id={"#{@id}-cost"}
          class="flex items-center gap-1 text-xs text-warning-ink"
        >
          <.icon name="warning" class="size-3.5" />
          {gettext(
            "Heavy query: the planner estimates a cost of %{cost}. Fewer rollups or a filter would lighten it.",
            cost: trunc(@cost.estimate)
          )}
        </p>
        <p :if={@group} id={"#{@id}-grouped"} class="flex items-center gap-1 text-xs text-ink-muted">
          {gettext("Grouped by %{column}", column: @group)}
          <.icon_button
            icon="close"
            context={:inline}
            label={gettext("Stop grouping")}
            id={"#{@id}-ungroup"}
            phx-click={@event}
            phx-target={@target}
            phx-value-op="group"
            phx-value-spec=""
          />
        </p>
        <p :if={@pivot} id={"#{@id}-pivoted"} class="flex items-center gap-1 text-xs text-ink-muted">
          {gettext("Pivoted by %{column}", column: @pivot)}
          <.icon_button
            icon="close"
            context={:inline}
            label={gettext("Stop pivoting")}
            id={"#{@id}-unpivot"}
            phx-click={@event}
            phx-target={@target}
            phx-value-op="pivot"
            phx-value-spec=""
          />
        </p>
        <div
          id={"#{@id}-group-zone"}
          data-group-zone
          class="hidden h-7 items-center rounded-md border border-dashed border-high-contrast-line px-2 text-xs text-ink-muted"
        >
          {gettext("Drop a column here to group by it")}
        </div>
        <div
          id={"#{@id}-pivot-zone"}
          data-pivot-zone
          class="hidden h-7 items-center rounded-md border border-dashed border-high-contrast-line px-2 text-xs text-ink-muted"
        >
          {if @group,
            do: gettext("Drop a column here to pivot by it"),
            else: gettext("Drop here to group first; the next drop pivots")}
        </div>
      </div>
      <div
        id={"#{@id}-viewport"}
        data-viewport
        class="relative overflow-auto border border-line bg-surface"
        tabindex="0"
      >
        <%= if @canvas? do %>
          <div id={"#{@id}-canvas-host"} phx-update="ignore" data-canvas-host class="relative">
            <canvas
              id={"#{@id}-canvas"}
              role="img"
              aria-label={
                gettext(
                  "%{rows} rows by %{columns} columns drawn as a %{mode} view; zoom in to read them",
                  rows: @total,
                  columns: length(@columns),
                  mode: String.downcase(@mode_label)
                )
              }
              class="sticky top-0 left-0 block"
            ></canvas>
            <div
              id={"#{@id}-tooltip"}
              role="status"
              aria-live="polite"
              class="pointer-events-none absolute z-20 hidden max-w-xs rounded-md border border-line bg-surface px-2 py-1 text-xs text-ink shadow-lg"
            >
            </div>
          </div>
        <% else %>
          <table class="w-full text-left text-sm">
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
                    "cursor-grab px-2 py-1.5 text-xs font-semibold text-ink-subtle",
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
                <th :if={@action != []} scope="col" class="px-2 py-1.5">
                  <span class="sr-only">{gettext("Actions")}</span>
                </th>
              </tr>
            </thead>
            <tbody id={"#{@id}-rows"} class="divide-y divide-low-contrast-line">
              <%= for {group, index} <- Enum.with_index(@groups), row <- [{:group, group, index} | group.rows] do %>
                <tr
                  :if={match?({:group, _, _}, row) and not is_nil(group.label)}
                  id={"#{@id}-group-#{index}"}
                  class="bg-surface-muted"
                >
                  <th
                    scope="rowgroup"
                    colspan={length(@columns) + if(@action != [], do: 1, else: 0)}
                    class="px-2 py-1 text-left text-xs font-semibold text-ink-subtle"
                  >
                    {group.label}
                    <span class="ml-1 font-normal tabular-nums text-ink-faint">({length(group.rows)})</span>
                  </th>
                </tr>
                <% row = if match?({:group, _, _}, row), do: nil, else: row %>
                <tr :if={row} id={@row_dom_id.(row.key)} class="hover:bg-surface-sunken">
                  <.flex_table_cell
                    :for={column <- @columns}
                    table_id={@id}
                    column={column}
                    row={row}
                    cell={Map.get(row.cells, column.id)}
                    slot={Map.get(@slots_by_id, column.id)}
                    expanded={@expanded |> Map.get(row.key, %{}) |> Map.has_key?(column.id)}
                    event={@event}
                    target={@target}
                  />
                  <td :if={@action != []} class="w-0 px-2 py-0.5 font-semibold">
                    <div class="flex items-center justify-end gap-1">
                      <%= for action <- @action do %>
                        {render_slot(action, row)}
                      <% end %>
                    </div>
                  </td>
                </tr>
                <tr
                  :for={
                    {column_id, opened} <- if(row, do: Map.get(@expanded, row.key, %{}), else: %{})
                  }
                  id={"#{@row_dom_id.(row.key)}-#{column_id}"}
                  class="bg-surface-muted"
                >
                  <td
                    colspan={length(@columns) + if(@action != [], do: 1, else: 0)}
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
                  colspan={length(@columns) + if(@action != [], do: 1, else: 0)}
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
        <% end %>
      </div>
    </div>
    """
  end

  attr(:table_id, :string, required: true)
  attr(:column, :map, required: true)
  attr(:row, :map, required: true)
  attr(:cell, :any, default: nil)
  attr(:slot, :any, default: nil)
  attr(:expanded, :boolean, default: false)
  attr(:event, :string, required: true)
  attr(:target, :any, default: nil)

  # One cell of the full table. A slot column defers to the caller; a rollup
  # is a button that opens the rows it collapsed beneath the row; a bar or a
  # band carries the data attributes the stylesheet and the hook paint from.
  defp flex_table_cell(%{slot: slot} = assigns) when not is_nil(slot) do
    assigns = assign(assigns, :cell_id, flex_table_cell_id(assigns))

    ~H"""
    <td
      id={@cell_id}
      class={["px-2 py-0.5 text-ink", Map.get(@column, :align) == :right && "text-right"]}
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
      class="px-2 py-0.5 text-ink tabular-nums"
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
        "px-2 py-0.5 text-ink",
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
      class="relative"
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
        class="peer grid size-5 place-items-center rounded-sm text-ink-muted transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong/40"
      >
        <.icon name={lens_icon(Map.get(@column, :lens, :value))} class="size-3" />
      </button>
      <div
        id={"#{@menu}-items"}
        class="hidden peer-aria-expanded:block absolute left-0 top-full z-30 mt-0.5 min-w-32 rounded-md border border-line bg-surface p-1 shadow-lg"
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
