defmodule Bilimbi.Base.Grid do
  @moduledoc """
  Flexible tables over the catalog every module declares.

  A module puts a table in the catalog through its `:grid` contribution:
  the table's fields, the links to other tables, the capability that reads
  it, and a `Bilimbi.Base.Grid.Source` that returns the rows a scope may
  see. From there a person builds a table by walking links, never by
  writing a join: `company.name` reaches a field through a one-link,
  `employees:count` rolls a many-link up into one cell, and the grid builds
  one statement for the whole set of columns.

  Every function takes the `Bilimbi.Base.Grid.Catalog` built for a scope by
  `catalog/1`, which already dropped the tables the actor may not read, so
  there is no path a person can spell that reaches one of them.
  """

  alias Bilimbi.Base.Grid.Catalog
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.Query
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope

  import Ecto.Query, only: [limit: 2, join: 5, select: 3, select_merge: 2, dynamic: 2]

  @expand_limit 50

  @doc "The catalog this scope may read."
  @spec catalog(Scope.t()) :: Catalog.t()
  def catalog(%Scope{} = scope), do: Catalog.for_scope(scope)

  @doc "A visible table by id."
  @spec fetch_table(Catalog.t(), String.t()) :: {:ok, Table.t()} | :error
  defdelegate fetch_table(catalog, id), to: Catalog

  @doc "Resolves column specs against a root table; see `Bilimbi.Base.Grid.Column`."
  @spec resolve(Catalog.t(), Table.t(), [String.t()]) ::
          {:ok, [Column.t()]} | {:error, {String.t(), term()}}
  defdelegate resolve(catalog, root, specs), to: Catalog, as: :resolve_all

  @doc "Columns a person could add, ranked against what they typed."
  @spec suggest(Catalog.t(), Table.t(), String.t(), keyword()) :: [Column.t()]
  defdelegate suggest(catalog, root, text, opts \\ []), to: Catalog

  @doc """
  The cells of `columns` for the root rows with these keys, keyed by row key.

  A page that already lists rows of its own uses this to add the columns a
  person walked to, without giving up its own query, filters or sort.
  """
  @spec attach(Catalog.t(), Table.t(), [term()], [Column.t()], keyword()) ::
          %{term() => %{cells: map(), series: map(), before: map()}}
  def attach(catalog, root, keys, columns, opts \\ [])
  def attach(%Catalog{}, %Table{}, [], _columns, _opts), do: %{}
  def attach(%Catalog{}, %Table{}, _keys, [], _opts), do: %{}

  def attach(%Catalog{} = catalog, %Table{} = root, keys, columns, opts) when is_list(keys) do
    plan =
      Query.plan(catalog, root, columns,
        trend: Keyword.get(opts, :trend, []),
        delta: Keyword.get(opts, :delta)
      )

    plan.query
    |> Query.with_keys(plan, keys)
    |> Query.select_rows(plan)
    |> Repo.all()
    |> Query.rows(plan)
    |> Map.new(&{&1.key, Map.take(&1, [:cells, :series, :before])})
  end

  @doc """
  The value range of numeric `columns` over every root row, for scaling
  bars and colours, with the planner's estimated cost of reading it.

  `attach/5` and `expand/4` read for one page of rows or one row; this is
  the statement that reads the whole table, so a caller shows its cost when
  it is heavy.
  """
  @spec stats(Catalog.t(), Table.t(), [Column.t()]) ::
          {%{String.t() => %{min: term(), max: term()}}, float() | nil}
  def stats(%Catalog{} = catalog, %Table{} = root, columns) when is_list(columns) do
    catalog |> Query.plan(root, columns) |> Query.stats()
  end

  @doc """
  The rows a rollup cell collapsed: the many-link's target rows for one
  root row, as maps of the target's visible fields, newest first when the
  target has a time field. At most #{@expand_limit} rows.
  """
  @spec expand(Catalog.t(), Table.t(), term(), Column.t()) ::
          {:ok, [map()]} | {:error, :not_a_rollup}
  def expand(%Catalog{} = catalog, %Table{} = root, key, %Column{kind: :rollup} = column) do
    target = fetch_table!(catalog, column.many.to)
    fields = Table.visible_fields(target)
    {:ok, [key_col]} = resolve(catalog, root, [root.key])
    plan = Query.plan(catalog, root, [key_col | hop_columns(catalog, root, column)])

    parent_binding = if column.hops == [], do: :root, else: :"j#{length(column.hops)}"

    parent_table =
      if column.hops == [], do: root, else: fetch_table!(catalog, List.last(column.hops).to)

    scope = catalog.scope

    query =
      case column.many do
        %{on: {from_field, to_field}} ->
          from_column = Map.fetch!(parent_table.fields, from_field).column
          to_column = Map.fetch!(target.fields, to_field).column

          join(
            plan.query,
            :inner,
            [{^parent_binding, p}],
            t in subquery(target.source.query(scope)),
            as: :expanded,
            on: field(p, ^from_column) == field(t, ^to_column)
          )

        %{via: {module, function}} ->
          parent_key = Table.key_field(parent_table).column
          target_key = Table.key_field(target).column

          plan.query
          |> join(:inner, [{^parent_binding, p}], e in subquery(apply(module, function, [scope])),
            as: :edge,
            on: field(p, ^parent_key) == e.from_key
          )
          |> join(:inner, [edge: e], t in subquery(target.source.query(scope)),
            as: :expanded,
            on: e.to_key == field(t, ^target_key)
          )
      end

    selected =
      Map.new(fields, fn field ->
        {field.column, dynamic([expanded: t], field(t, ^field.column))}
      end)

    rows =
      query
      |> Query.with_keys(plan, [key])
      |> select([], %{})
      |> select_merge(^selected)
      |> order_expanded(target)
      |> limit(@expand_limit)
      |> Repo.all()
      |> Enum.map(fn row -> Map.new(fields, &{&1.id, Map.get(row, &1.column)}) end)

    {:ok, rows}
  end

  def expand(%Catalog{}, %Table{}, _key, %Column{}), do: {:error, :not_a_rollup}

  # The joins a rollup's prefix needs, as columns the plan can build from.
  defp hop_columns(_catalog, _root, %Column{hops: []}), do: []

  defp hop_columns(catalog, root, %Column{hops: hops}) do
    last = fetch_table!(catalog, List.last(hops).to)
    spec = Enum.map_join(hops, ".", & &1.id) <> "." <> last.key
    {:ok, [column]} = resolve(catalog, root, [spec])
    [column]
  end

  defp order_expanded(query, %Table{time_field: nil} = target) do
    key = Table.key_field(target).column
    Ecto.Query.order_by(query, [expanded: t], asc: field(t, ^key))
  end

  defp order_expanded(query, %Table{time_field: time_field} = target) do
    time = Map.fetch!(target.fields, time_field).column
    key = Table.key_field(target).column

    Ecto.Query.order_by(query, [expanded: t],
      desc_nulls_last: field(t, ^time),
      asc: field(t, ^key)
    )
  end

  defp fetch_table!(catalog, id) do
    case Catalog.fetch_table(catalog, id) do
      {:ok, table} -> table
      :error -> raise ArgumentError, "table #{inspect(id)} is not in this catalog"
    end
  end
end
