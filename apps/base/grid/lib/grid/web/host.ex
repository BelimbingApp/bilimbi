defmodule Bilimbi.Base.Grid.Web.Host do
  @moduledoc """
  The vocabulary between `flex_table/1` and the page that hosts it: turn
  resolved columns into the component's column maps, prepare cells through
  their lenses, and turn the component's one event into a change of the
  view.

  `Bilimbi.Base.Grid.Web.PageColumns` is the host; it applies each `op`
  with `apply/3`, whose result says whether to patch the URL with a new
  view, answer a suggestion request, or open or close a rollup.
  """

  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Catalog
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.Lens
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Grid.View

  @heavy_cost 20_000.0

  @doc """
  The column maps `flex_table/1` takes, with each column's lens from the
  view. A walked column never sorts: the page owns the order of its rows.
  """
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
        sortable: false,
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

  @doc "The columns whose lens is `lens` in the view."
  @spec with_lens([Column.t()], View.t(), Lens.lens()) :: [Column.t()]
  def with_lens(columns, %View{} = view, lens),
    do: Enum.filter(columns, &(lens(view, &1) == lens))

  @doc "The `:trend` and `:delta` options `Grid.attach/5` takes for this view."
  @spec lens_options([Column.t()], View.t()) :: keyword()
  def lens_options(columns, %View{} = view) do
    [
      trend: with_lens(columns, view, :trend),
      delta:
        {with_lens(columns, view, :delta), NaiveDateTime.new!(View.since(view), ~T[00:00:00])}
    ]
  end

  @doc "Prepared cells for rows a page already has, from values `Grid.attach/5` returned."
  @spec attached_cells(%{term() => %{String.t() => term()}}, [Column.t()], map(), View.t()) ::
          %{term() => %{String.t() => Lens.cell()}}
  def attached_cells(values, columns, stats, %View{} = view) do
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
               before: get_in(attached, [:before, column.id])
             }
           )}
        end)

      {key, prepared}
    end)
  end

  @doc """
  The view's columns in order: a page's own built-in column as its id, a
  walked column as the `Column` the catalog resolves it to. Built-ins keep
  the page's order when the view names none of them. A spec the catalog
  refuses is left out.
  """
  @spec split_columns(Catalog.t(), Table.t(), View.t(), [String.t()]) ::
          [String.t() | Column.t()]
  def split_columns(%Catalog{} = catalog, %Table{} = root, %View{columns: specs}, builtin_ids) do
    specs = if specs == [], do: builtin_ids, else: specs

    Enum.flat_map(specs, fn spec ->
      if spec in builtin_ids do
        [spec]
      else
        case Catalog.resolve(catalog, root, spec) do
          {:ok, column} -> [column]
          {:error, _reason} -> []
        end
      end
    end)
  end

  @doc """
  A planner estimate as the component shows it: heavy above #{trunc(@heavy_cost)}. `nil`
  when nothing was estimated.
  """
  @spec cost(float() | nil) :: %{estimate: float(), heavy?: boolean()} | nil
  def cost(nil), do: nil
  def cost(cost) when is_float(cost), do: %{estimate: cost, heavy?: cost > @heavy_cost}

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
          | {:add_typed, String.t()}
          | {:expand, String.t(), String.t()}
          | {:collapse, String.t(), String.t()}
          | :noop

  @doc """
  Applies one component `op` to the view. `columns` are the resolved walked
  columns, so a lens on a spec the table does not show is ignored. Sorting
  is the page's own and never arrives here.
  """
  @spec apply(map(), View.t(), [Column.t()]) :: outcome()
  def apply(%{"op" => "suggest"} = params, _view, _columns), do: {:suggest, typed(params)}

  def apply(%{"op" => "add", "spec" => spec}, view, _columns) when is_binary(spec),
    do: {:patch, View.add_column(view, spec)}

  def apply(%{"op" => "add_typed"} = params, _view, _columns) do
    case typed(params) do
      "" -> :noop
      text -> {:add_typed, text}
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

  def apply(%{"op" => "density"} = params, view, _columns),
    do: {:patch, View.put_density(view, params["density"])}

  def apply(%{"op" => "since"} = params, view, _columns),
    do: {:patch, View.put_since(view, params["since"])}

  def apply(%{"op" => "expand", "spec" => spec, "key" => key}, _view, columns)
      when is_binary(spec) do
    if Enum.any?(columns, &(&1.spec == spec and &1.kind == :rollup)),
      do: {:expand, spec, to_string(key)},
      else: :noop
  end

  def apply(%{"op" => "collapse", "spec" => spec, "key" => key}, _view, _columns)
      when is_binary(spec),
      do: {:collapse, spec, to_string(key)}

  def apply(_params, _view, _columns), do: :noop

  defp typed(params),
    do: params |> Map.get("add", "") |> to_string() |> String.trim() |> String.slice(0, 120)
end
