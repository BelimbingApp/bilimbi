defmodule Bilimbi.Base.Grid.Web.PageColumns do
  @moduledoc """
  Walked columns for a list page that already has rows of its own.

  A list page keeps its query, filters, sort and pagination, and declares
  the columns it draws itself as built-ins. This struct adds everything the
  grid brings on top: columns a person walks to through the catalog (added,
  removed, reordered and read through lenses), the zoom, rollups that
  expand in place, and the canvas modes. The page's rows stay the rows; the
  walked columns are fetched for exactly those rows with `Grid.attach/4`.

  The page holds one `%PageColumns{}` in its assigns and:

    1. builds it at mount with `mount/3`;
    2. reads `cols`, `lens` and `z` from the URL with `from_params/2` and
       merges `params/1` back into every path it patches to;
    3. after loading its page, calls `load/4` with the entries, a key
       function and a function giving each built-in's cell values;
    4. renders `flex_table/1` from `column_views`, `rows`, `mode` and the
       view, with a `<:col>` slot per built-in id;
    5. delegates its `"grid"` event to `handle/2`.

  A page whose table is not in the account's catalog still works: the
  built-ins render and the add bar offers nothing.
  """

  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.Lens
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Grid.Web.Host
  alias Bilimbi.Base.Grid.Zoom
  alias Bilimbi.Base.Tenancy.Scope

  @enforce_keys [:catalog, :table, :builtins, :view]
  defstruct catalog: nil,
            table: nil,
            builtins: [],
            view: %View{},
            extras: [],
            dropped: [],
            column_views: [],
            rows: [],
            mode: :full,
            suggestions: [],
            add_query: "",
            expanded: %{},
            total: 0

  @type builtin :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:type) => Column.t() | atom(),
          optional(:sort) => String.t(),
          optional(:sort_id) => String.t(),
          optional(:align) => :right | nil
        }

  @type t :: %__MODULE__{}

  @doc "Builds the state for a page whose rows are `table_id` rows, with its built-in columns."
  @spec mount(Scope.t(), String.t(), [builtin()]) :: t()
  def mount(%Scope{} = scope, table_id, builtins) when is_list(builtins) do
    catalog = Grid.catalog(scope)

    table =
      case Grid.fetch_table(catalog, table_id) do
        {:ok, table} -> table
        :error -> nil
      end

    %__MODULE__{catalog: catalog, table: table, builtins: builtins, view: %View{table: table_id}}
  end

  @doc "Reads the walked columns, lenses and zoom from URL params."
  @spec from_params(t(), map()) :: t()
  def from_params(%__MODULE__{} = state, params) do
    incoming = View.from_params(params, state.view.table)
    view = %{state.view | columns: incoming.columns, lenses: incoming.lenses, zoom: incoming.zoom}
    %{state | view: view, suggestions: [], add_query: "", expanded: %{}}
  end

  @doc "The URL params a page merges into its own: only what differs from the defaults."
  @spec params(t()) :: map()
  def params(%__MODULE__{view: view}) do
    View.to_params(%{
      view
      | sort: nil,
        dir: :asc,
        search: "",
        page: 1,
        page_size: 25,
        group: nil,
        slug: nil
    })
  end

  @doc """
  Prepares the component's columns and rows for this page of entries.
  `key` gives a row's key, `builtin_cells` the values of the built-in
  columns for one entry as `%{id => value}`, so the compact and carpet
  modes can draw them too.
  """
  @spec load(t(), [term()], (term() -> term()), (term() -> map())) :: t()
  def load(%__MODULE__{} = state, entries, key, builtin_cells)
      when is_list(entries) and is_function(key, 1) and is_function(builtin_cells, 1) do
    builtin_ids = Enum.map(state.builtins, & &1.id)

    {kept, dropped} =
      case state.table do
        nil ->
          {Enum.filter(state.view.columns, &(&1 in builtin_ids)),
           state.view.columns -- builtin_ids}

        table ->
          Host.split_columns(state.catalog, table, state.view, builtin_ids)
      end

    kept = if kept == [], do: builtin_ids, else: kept
    extras = Enum.filter(kept, &is_struct(&1, Column))
    kept_specs = Enum.map(kept, &if(is_binary(&1), do: &1, else: &1.spec))
    # The page's own order with nothing walked is the default, and the URL
    # says nothing about a default.
    view = %{state.view | columns: if(kept_specs == builtin_ids, do: [], else: kept_specs)}
    keys = Enum.map(entries, key)

    values =
      if extras == [] or state.table == nil,
        do: %{},
        else: Grid.attach(state.catalog, state.table, keys, extras)

    stats =
      if extras == [] or state.table == nil or
           not Enum.any?(extras, &(Host.lens(view, &1) != :value)),
         do: %{},
         else: Grid.stats(state.catalog, state.table, extras)

    extra_cells = Host.attached_cells(values, extras, stats, view)
    builtin_map = Map.new(state.builtins, &{&1.id, &1})

    column_views =
      Enum.map(kept, fn
        id when is_binary(id) ->
          builtin_view(Map.fetch!(builtin_map, id))

        %Column{} = column ->
          column |> List.wrap() |> Host.column_views(view) |> hd() |> Map.put(:sortable, false)
      end)

    rows =
      Enum.map(entries, fn entry ->
        row_key = key.(entry)

        cells =
          entry
          |> builtin_cells.()
          |> Map.new(fn {id, value} -> {id, plain_cell(value)} end)
          |> Map.merge(Map.get(extra_cells, row_key, %{}))

        %{key: row_key, cells: cells}
      end)

    %{
      state
      | view: view,
        extras: extras,
        dropped: dropped,
        column_views: column_views,
        rows: rows,
        mode: Zoom.mode(view.zoom),
        total: length(rows)
    }
  end

  defp builtin_view(builtin) do
    %{
      id: builtin.id,
      spec: builtin.id,
      label: builtin.label,
      short_label: builtin.label,
      type: builtin.type,
      kind: :slot,
      lens: :value,
      lenses: [:value],
      sortable: Map.has_key?(builtin, :sort),
      sort_id: Map.get(builtin, :sort_id),
      removable: true,
      align: Map.get(builtin, :align)
    }
  end

  defp plain_cell(nil), do: %{text: "", value: nil, n: nil, band: nil, scale: nil}

  defp plain_cell(value) do
    %{text: plain_text(value), value: value, n: nil, band: nil, scale: nil}
  end

  defp plain_text(%NaiveDateTime{} = naive),
    do: naive |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp plain_text(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()
  defp plain_text(list) when is_list(list), do: Enum.map_join(list, ", ", &plain_text/1)
  defp plain_text(other), do: to_string(other)

  @type outcome ::
          {:patch, t()}
          | {:update, t()}
          | {:sort, String.t()}
          | {:window, String.t(), map()}
          | {:reply, String.t() | nil}
          | :noop

  @doc "Applies one `flex_table` op. `table_id` is the component's DOM id, which names its window event."
  @spec handle(t(), map(), String.t()) :: outcome()
  def handle(%__MODULE__{} = state, params, table_id)
      when is_map(params) and is_binary(table_id) do
    builtin_sorts = state.builtins |> Enum.filter(&Map.has_key?(&1, :sort)) |> Enum.map(& &1.id)
    # An empty column list means the page default; an op that changes columns
    # starts from that default spelled out, so a built-in is never lost.
    state =
      if state.view.columns == [],
        do: %{state | view: %{state.view | columns: Enum.map(state.builtins, & &1.id)}},
        else: state

    case params do
      %{"op" => "sort", "sort" => spec} ->
        if spec in builtin_sorts, do: {:sort, spec}, else: :noop

      %{"op" => "group"} ->
        :noop

      %{"op" => "add_typed"} = params ->
        add_typed(state, Map.get(params, "add", ""))

      _other ->
        case Host.apply(params, state.view, state.extras) do
          {:patch, view} ->
            {:patch, %{state | view: view}}

          {:suggest, text} ->
            {:update, suggest(state, text)}

          {:expand, spec, key} ->
            {:update, expand(state, spec, key)}

          {:collapse, spec, key} ->
            {:update, collapse(state, spec, key)}

          {:window, _offset, _limit, detail} ->
            {:window, "#{table_id}:window",
             Host.window_payload_from_rows(state.rows, state.column_views, 0, state.total, detail)}

          {:cell, row, column_id} ->
            {:reply, cell_text(state, row, column_id)}

          {:scroll, view, _row, _col} ->
            {:patch, %{state | view: view}}

          {:add_typed, text, _view} ->
            add_typed(state, text)

          :noop ->
            :noop
        end
    end
  end

  defp suggest(%{table: nil} = state, text), do: %{state | add_query: text, suggestions: []}

  defp suggest(state, text) do
    suggestions =
      if text == "",
        do: [],
        else: Grid.suggest(state.catalog, state.table, text, exclude: state.view.columns)

    %{state | add_query: text, suggestions: Host.column_views(suggestions, state.view)}
  end

  defp add_typed(%{table: nil}, _text), do: :noop
  defp add_typed(_state, ""), do: :noop

  defp add_typed(state, text) do
    text = String.trim(text)

    resolved =
      case Grid.resolve(state.catalog, state.table, [text]) do
        {:ok, [column]} ->
          column.spec

        {:error, _reason} ->
          state.catalog
          |> Grid.suggest(state.table, text, exclude: state.view.columns, limit: 1)
          |> Enum.map(& &1.spec)
          |> List.first()
      end

    case resolved do
      nil ->
        :noop

      spec ->
        {:patch,
         %{state | view: View.add_column(state.view, spec), suggestions: [], add_query: ""}}
    end
  end

  defp expand(state, spec, key) do
    with %Column{} = column <- Enum.find(state.extras, &(&1.spec == spec)),
         %{key: row_key} <- Enum.find(state.rows, &(to_string(&1.key) == key)) do
      rows = Host.expansion(state.catalog, state.table, row_key, column)

      %{
        state
        | expanded:
            Map.update(
              state.expanded,
              row_key,
              %{column.id => rows},
              &Map.put(&1, column.id, rows)
            )
      }
    else
      _other -> state
    end
  end

  defp collapse(state, spec, key) do
    with %Column{} = column <- Enum.find(state.extras, &(&1.spec == spec)),
         %{key: row_key} <- Enum.find(state.rows, &(to_string(&1.key) == key)) do
      %{state | expanded: Map.update(state.expanded, row_key, %{}, &Map.delete(&1, column.id))}
    else
      _other -> state
    end
  end

  defp cell_text(state, row_index, column_id) do
    with %{cells: cells} <- Enum.at(state.rows, row_index),
         %{text: text} <- Map.get(cells, column_id) do
      text
    else
      _other -> nil
    end
  end

  @doc "The component's `sort_dir` atom from a page's own direction value."
  @spec sort_dir(term()) :: :asc | :desc
  def sort_dir(dir) when dir in [:desc, "desc"], do: :desc
  def sort_dir(_dir), do: :asc

  @doc "Whether this table lives in the account's catalog (so the add bar has something to offer)."
  @spec catalog?(t()) :: boolean()
  def catalog?(%__MODULE__{table: %Table{}}), do: true
  def catalog?(%__MODULE__{}), do: false

  @doc false
  def lens_text(value, %Column{} = column), do: Lens.text(value, column)
end
