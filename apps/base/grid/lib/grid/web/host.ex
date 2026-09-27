defmodule Bilimbi.Base.Grid.Web.Host do
  @moduledoc """
  What every page that hosts a `flex_table` does the same way: turn resolved
  columns into the component's column maps, prepare cells through their
  lenses, build the window the hook draws from, and turn the component's
  one event into a change of the view.

  A host keeps a `Bilimbi.Base.Grid.View` in the URL and applies each `op`
  with `apply/3`: the result says whether to patch the URL with a new view,
  answer a suggestion request, open or close a rollup, serve a window, or
  answer a hover. The grid page and a list page that adds walked columns
  share this so the same gesture means the same thing on both.
  """

  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Catalog
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.Lens
  alias Bilimbi.Base.Grid.Result
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Grid.Zoom

  @heavy_cost 20_000.0

  @doc "The planner cost above which the toolbar warns."
  @spec heavy_cost() :: float()
  def heavy_cost, do: @heavy_cost

  @doc "Resolves the view's columns, dropping any spec the catalog refuses, and reports the drops."
  @spec resolve_columns(Catalog.t(), Table.t(), View.t()) :: {[Column.t()], [String.t()]}
  def resolve_columns(%Catalog{} = catalog, %Table{} = root, %View{columns: []}) do
    {Grid.default_columns(catalog, root), []}
  end

  def resolve_columns(%Catalog{} = catalog, %Table{} = root, %View{columns: specs}) do
    {columns, dropped} =
      Enum.reduce(specs, {[], []}, fn spec, {columns, dropped} ->
        case Catalog.resolve(catalog, root, spec) do
          {:ok, column} -> {[column | columns], dropped}
          {:error, _reason} -> {columns, [spec | dropped]}
        end
      end)

    columns = Enum.reverse(columns)
    columns = if columns == [], do: Grid.default_columns(catalog, root), else: columns
    {columns, Enum.reverse(dropped)}
  end

  @doc "The column maps `flex_table/1` takes, with each column's lens from the view."
  @spec column_views([Column.t()], View.t(), keyword()) :: [map()]
  def column_views(columns, %View{} = view, opts \\ []) do
    removable = Keyword.get(opts, :removable, true)

    Enum.map(columns, fn %Column{} = column ->
      %{
        id: column.id,
        spec: column.spec,
        label: column.label,
        short_label: column.short_label,
        type: column.type,
        kind: column.kind,
        lens: lens(view, column),
        lenses: Lens.available(column),
        sortable: column.sortable,
        removable: removable,
        align: if(Column.numeric?(column), do: :right)
      }
    end)
  end

  @doc "The lens the view holds for a column, normalized to what it allows."
  @spec lens(View.t(), Column.t()) :: Lens.lens()
  def lens(%View{lenses: lenses}, %Column{} = column) do
    Lens.normalize(Map.get(lenses, column.spec, "value"), column)
  end

  @doc "The rows `flex_table/1` takes: every cell prepared through its column's lens and the set's stats."
  @spec rows(Result.t(), View.t()) :: [%{key: term(), cells: %{String.t() => Lens.cell()}}]
  def rows(%Result{} = result, %View{} = view) do
    since = View.since(view)

    Enum.map(result.rows, fn row ->
      cells =
        Map.new(result.columns, fn column ->
          value = Map.get(row.cells, column.id)

          {column.id,
           Lens.cell(value, column, Map.get(result.stats, column.id), lens(view, column), %{
             series: get_in(row, [:series, column.id]),
             before: get_in(row, [:before, column.id]),
             since: since
           })}
        end)

      %{key: row.key, cells: cells}
    end)
  end

  @doc "The columns whose lens is `lens` in the view."
  @spec with_lens([Column.t()], View.t(), Lens.lens()) :: [Column.t()]
  def with_lens(columns, %View{} = view, lens),
    do: Enum.filter(columns, &(lens(view, &1) == lens))

  @doc "The `:trend` and `:delta` options `Grid.query/4` and `Grid.attach/5` take for this view."
  @spec lens_options([Column.t()], View.t()) :: keyword()
  def lens_options(columns, %View{} = view) do
    [
      trend: with_lens(columns, view, :trend),
      delta:
        {with_lens(columns, view, :delta), NaiveDateTime.new!(View.since(view), ~T[00:00:00])}
    ]
  end

  @doc "Prepared cells for rows a page already has, from values `Grid.attach/4` returned."
  @spec attached_cells(%{term() => %{String.t() => term()}}, [Column.t()], map(), View.t()) ::
          %{term() => %{String.t() => Lens.cell()}}
  def attached_cells(values, columns, stats, %View{} = view) do
    since = View.since(view)

    Map.new(values, fn {key, attached} ->
      cells = Map.get(attached, :cells, %{})

      prepared =
        Map.new(columns, fn column ->
          {column.id,
           Lens.cell(
             Map.get(cells, column.id),
             column,
             Map.get(stats, column.id),
             lens(view, column),
             %{
               series: get_in(attached, [:series, column.id]),
               before: get_in(attached, [:before, column.id]),
               since: since
             }
           )}
        end)

      {key, prepared}
    end)
  end

  @doc """
  The window payload the hook draws from: `[key, [[text, n, band, scale], ...]]`
  per row. `:levels` detail leaves the text out, which is what the carpet
  needs; a hover asks for one cell's text instead.
  """
  @spec window_payload(Result.t(), View.t(), :levels | :text) :: map()
  def window_payload(%Result{} = result, %View{} = view, detail) do
    rows =
      result
      |> rows(view)
      |> Enum.map(fn row ->
        cells =
          Enum.map(result.columns, fn column ->
            cell = Map.fetch!(row.cells, column.id)
            [if(detail == :text, do: cell.text), cell.n, cell.band, cell.scale, cell.series]
          end)

        [row.key, cells]
      end)

    %{offset: result.offset, total: result.total_entries, rows: rows}
  end

  @doc """
  Splits a view's columns between a page's own built-in columns, by id, and
  the specs the catalog resolves. Built-ins keep the page's order when the
  view names none of them. Specs the catalog refuses are dropped.
  """
  @spec split_columns(Catalog.t(), Table.t(), View.t(), [String.t()]) ::
          {[String.t() | Column.t()], [String.t()]}
  def split_columns(%Catalog{} = catalog, %Table{} = root, %View{columns: specs}, builtin_ids) do
    specs = if specs == [], do: builtin_ids, else: specs

    Enum.reduce(specs, {[], []}, fn spec, {kept, dropped} ->
      cond do
        spec in builtin_ids ->
          {kept ++ [spec], dropped}

        true ->
          case Catalog.resolve(catalog, root, spec) do
            {:ok, column} -> {kept ++ [column], dropped}
            {:error, _reason} -> {kept, dropped ++ [spec]}
          end
      end
    end)
  end

  @doc "A window payload from rows already prepared for the component."
  @spec window_payload_from_rows(
          [map()],
          [map()],
          non_neg_integer(),
          non_neg_integer(),
          :levels | :text
        ) ::
          map()
  def window_payload_from_rows(rows, column_views, offset, total, detail) do
    rows =
      Enum.map(rows, fn row ->
        cells =
          Enum.map(column_views, fn column ->
            case Map.get(row.cells, column.id) do
              nil ->
                [nil, nil, nil, nil, nil]

              cell ->
                [
                  if(detail == :text, do: cell.text),
                  cell.n,
                  cell.band,
                  cell.scale,
                  Map.get(cell, :series)
                ]
            end
          end)

        [row.key, cells]
      end)

    %{offset: offset, total: total, rows: rows}
  end

  @doc "The planner estimate as the component shows it."
  @spec cost(Result.t()) :: %{estimate: float(), heavy?: boolean()} | nil
  def cost(%Result{cost: nil}), do: nil
  def cost(%Result{cost: cost}), do: %{estimate: cost, heavy?: cost > @heavy_cost}

  @doc "The rows a rollup collapsed, with every value as text for the expansion table."
  @spec expansion(Catalog.t(), Table.t(), term(), Column.t()) :: [map()]
  def expansion(%Catalog{} = catalog, %Table{} = root, key, %Column{} = column) do
    labels =
      case Catalog.fetch_table(catalog, column.many.to) do
        {:ok, target} -> Map.new(target.fields, fn {id, field} -> {id, field.label} end)
        :error -> %{}
      end

    case Grid.expand(catalog, root, key, column) do
      {:ok, rows} ->
        Enum.map(rows, fn row ->
          Map.new(row, fn {field, value} ->
            {Map.get(labels, field, field), Lens.text(value, column)}
          end)
        end)

      {:error, _reason} ->
        []
    end
  end

  @type outcome ::
          {:patch, View.t()}
          | {:suggest, String.t()}
          | {:expand, String.t(), String.t()}
          | {:collapse, String.t(), String.t()}
          | {:window, non_neg_integer(), pos_integer(), :levels | :text}
          | {:cell, non_neg_integer(), String.t()}
          | {:scroll, View.t(), non_neg_integer(), non_neg_integer()}
          | :noop

  @doc """
  Applies one component `op` to the view. `columns` are the resolved
  columns, so a sort or lens on a spec the grid does not show is ignored.
  """
  @spec apply(map(), View.t(), [Column.t()]) :: outcome()
  def apply(%{"op" => "suggest"} = params, _view, _columns), do: {:suggest, typed(params)}

  def apply(%{"op" => "add", "spec" => spec}, view, _columns) when is_binary(spec),
    do: {:patch, View.add_column(view, spec)}

  def apply(%{"op" => "add_typed"} = params, view, _columns) do
    case typed(params) do
      "" -> :noop
      text -> {:add_typed, text, view}
    end
  end

  def apply(%{"op" => "remove", "spec" => spec}, view, _columns) when is_binary(spec),
    do: {:patch, View.remove_column(view, spec)}

  def apply(%{"op" => "move", "spec" => spec} = params, view, _columns) when is_binary(spec) do
    before = Map.get(params, "before")
    {:patch, View.move_column(view, spec, if(is_binary(before) and before != "", do: before))}
  end

  def apply(%{"op" => "lens", "spec" => spec, "lens" => lens}, view, columns)
      when is_binary(spec) and is_binary(lens) do
    case Enum.find(columns, &(&1.spec == spec)) do
      nil -> :noop
      column -> {:patch, View.put_lens(view, spec, Atom.to_string(Lens.normalize(lens, column)))}
    end
  end

  def apply(%{"op" => "sort", "sort" => spec}, view, columns) when is_binary(spec) do
    if Enum.any?(columns, &(&1.spec == spec and &1.sortable)),
      do: {:patch, View.sort_by(view, spec)},
      else: :noop
  end

  def apply(%{"op" => "zoom", "dir" => dir}, view, _columns) when dir in ["in", "out"] do
    {:patch, %{view | zoom: Zoom.step(view.zoom, if(dir == "in", do: :in, else: :out)), page: 1}}
  end

  def apply(%{"op" => "zoom_preset", "z" => z}, view, _columns) do
    {:patch, %{view | zoom: Zoom.normalize(z), page: 1}}
  end

  def apply(%{"op" => "zoom_rect"} = params, view, columns) do
    from_row = integer(params["from_row"], 0)
    to_row = max(integer(params["to_row"], from_row + 1), from_row + 1)
    from_col = integer(params["from_col"], 0)
    to_col = max(integer(params["to_col"], from_col + 1), from_col + 1)
    width = integer(params["width"], 1200)
    height = integer(params["height"], 600)

    zoom =
      Zoom.fit(to_row - from_row, min(to_col - from_col, max(length(columns), 1)), width, height)

    view = %{view | zoom: zoom}

    if Zoom.mode(zoom) == :full do
      {:patch, %{view | page: div(from_row, view.page_size) + 1}}
    else
      {:scroll, view, from_row, from_col}
    end
  end

  def apply(%{"op" => "expand", "spec" => spec, "key" => key}, _view, columns)
      when is_binary(spec) do
    if Enum.any?(columns, &(&1.spec == spec and &1.kind == :rollup)),
      do: {:expand, spec, to_string(key)},
      else: :noop
  end

  def apply(%{"op" => "collapse", "spec" => spec, "key" => key}, _view, _columns)
      when is_binary(spec),
      do: {:collapse, spec, to_string(key)}

  def apply(%{"op" => "group", "spec" => spec}, view, columns) when is_binary(spec) do
    cond do
      spec == "" ->
        {:patch, %{view | group: nil}}

      Enum.any?(columns, &(&1.spec == spec and &1.sortable)) ->
        {:patch, %{view | group: spec, sort: spec, dir: :asc, page: 1}}

      true ->
        :noop
    end
  end

  def apply(%{"op" => "window"} = params, _view, _columns) do
    offset = integer(params["offset"], 0)
    limit = params["limit"] |> integer(200) |> max(1) |> min(Grid.max_limit())
    {:window, offset, limit, if(params["detail"] == "levels", do: :levels, else: :text)}
  end

  def apply(%{"op" => "cell"} = params, _view, _columns) do
    {:cell, integer(params["row"], 0), to_string(params["col"] || "")}
  end

  def apply(_params, _view, _columns), do: :noop

  defp typed(params),
    do: params |> Map.get("add", "") |> to_string() |> String.trim() |> String.slice(0, 120)

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp integer(_value, default), do: default
end
