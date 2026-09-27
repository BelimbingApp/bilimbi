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
  alias Bilimbi.Base.Grid.Lens
  alias Bilimbi.Base.Grid.Query
  alias Bilimbi.Base.Grid.Result
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope

  import Ecto.Query, only: [limit: 2, offset: 2, join: 5, select: 3, select_merge: 2, dynamic: 2]

  @default_limit 50
  @max_limit 5000
  @expand_limit 50

  @doc "The catalog this scope may read."
  @spec catalog(Scope.t()) :: Catalog.t()
  def catalog(%Scope{} = scope), do: Catalog.for_scope(scope)

  @doc "A visible table by id."
  @spec fetch_table(Catalog.t(), String.t()) :: {:ok, Table.t()} | :error
  defdelegate fetch_table(catalog, id), to: Catalog

  @doc "The visible tables, by label."
  @spec tables(Catalog.t()) :: [Table.t()]
  defdelegate tables(catalog), to: Catalog

  @doc "Resolves column specs against a root table; see `Bilimbi.Base.Grid.Column`."
  @spec resolve(Catalog.t(), Table.t(), [String.t()]) ::
          {:ok, [Column.t()]} | {:error, {String.t(), term()}}
  defdelegate resolve(catalog, root, specs), to: Catalog, as: :resolve_all

  @doc "The columns a table starts with: its own visible fields."
  @spec default_columns(Catalog.t(), Table.t()) :: [Column.t()]
  defdelegate default_columns(catalog, root), to: Catalog

  @doc "Columns a person could add, ranked against what they typed."
  @spec suggest(Catalog.t(), Table.t(), String.t(), keyword()) :: [Column.t()]
  defdelegate suggest(catalog, root, text, opts \\ []), to: Catalog

  @doc """
  Runs the grid: a window of rows, the total, the value range of every
  numeric column, and the planner's cost estimate.

  Options: `:offset` and `:limit` (at most #{@max_limit}) choose the window,
  `:sort` a `{column, :asc | :desc}` pair, `:search` text matched against the
  root's searchable fields, `:focus` a `{:root | column, key}` pair that keeps
  only the rows reaching one record (see `focus_column/3`), `:trend` the
  rollup columns whose last twelve months come back as a `series`, `:delta`
  a `{columns, since}` pair whose aggregate as of `since` comes back as
  `before`, and `:stats`,
  `:cost` and `:count` (each default
  true) switch the extra statements off when a caller does not show them or
  already holds the total; with `count: false` the result's `total_entries`
  is the `:total` option, or 0.
  """
  @spec query(Catalog.t(), Table.t(), [Column.t()], keyword()) :: Result.t()
  def query(%Catalog{} = catalog, %Table{} = root, columns, opts \\ []) when is_list(columns) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> max(1) |> min(@max_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)
    {sort_column, dir} = Keyword.get(opts, :sort, {nil, :asc})

    focus = Keyword.get(opts, :focus)

    plan =
      Query.plan(catalog, root, columns,
        extra: focus_columns(focus),
        trend: Keyword.get(opts, :trend, []),
        delta: Keyword.get(opts, :delta)
      )

    base =
      plan.query
      |> Query.search(root, Keyword.get(opts, :search))
      |> focus_rows(plan, focus)

    rows_query =
      base
      |> Query.select_rows(plan)
      |> Query.order(plan, sort_column, dir)
      |> limit(^limit)
      |> offset(^offset)

    %Result{
      columns: columns,
      rows: rows_query |> Repo.all() |> Query.rows(plan),
      total_entries:
        if(Keyword.get(opts, :count, true),
          do: Query.count(base, plan),
          else: Keyword.get(opts, :total, 0)
        ),
      offset: offset,
      limit: limit,
      stats: if(Keyword.get(opts, :stats, true), do: Query.stats(base, plan), else: %{}),
      cost: if(Keyword.get(opts, :cost, true), do: Query.estimated_cost(rows_query), else: nil)
    }
  end

  defp focus_columns({%Column{} = column, _id}), do: [column]
  defp focus_columns(_focus), do: []

  defp focus_rows(query, plan, {:root, id}), do: Query.focus(query, plan, :root, id)
  defp focus_rows(query, plan, {%Column{} = column, id}), do: Query.focus(query, plan, column, id)
  defp focus_rows(query, _plan, _focus), do: query

  @doc """
  What a grid follows for a selected record of `kind`: `{:root, key_field}`
  when the root table records that kind, or `{column, key_field}` for the
  one-link `follow` whose target does, the column being that target's key
  reached through the link. `:error` when neither holds, so a follow
  written into a URL for another table means nothing here.

  A selected key arrives as text; `key_field` tells the caller how to read
  it before passing it as `focus:`.
  """
  @spec focus_column(Catalog.t(), Table.t(), String.t()) ::
          {:ok, :root | Column.t(), Bilimbi.Base.Grid.Field.t(), String.t()} | :error
  def focus_column(%Catalog{}, %Table{record_kind: kind} = root, "self") when is_binary(kind) do
    {:ok, :root, Table.key_field(root), kind}
  end

  def focus_column(%Catalog{} = catalog, %Table{} = root, follow) when is_binary(follow) do
    with %{kind: :one, to: to} <- Map.get(root.links, follow),
         {:ok, %Table{record_kind: kind} = target} when is_binary(kind) <-
           fetch_table(catalog, to),
         {:ok, [column]} <- resolve(catalog, root, ["#{follow}.#{target.key}"]) do
      {:ok, column, Table.key_field(target), kind}
    else
      _other -> :error
    end
  end

  def focus_column(%Catalog{}, %Table{}, _follow), do: :error

  @doc """
  The ways this grid can follow a workspace selection: `"self"` when the
  root table records a kind, and each one-link whose target does, with the
  kind followed and the label to offer.
  """
  @spec follow_options(Catalog.t(), Table.t()) :: [
          %{follow: String.t(), kind: String.t(), label: String.t()}
        ]
  def follow_options(%Catalog{} = catalog, %Table{} = root) do
    own =
      if root.record_kind,
        do: [%{follow: "self", kind: root.record_kind, label: root.label}],
        else: []

    linked =
      root
      |> Table.links()
      |> Enum.filter(&(&1.kind == :one))
      |> Enum.flat_map(fn link ->
        case fetch_table(catalog, link.to) do
          {:ok, %Table{record_kind: kind}} when is_binary(kind) ->
            [%{follow: link.id, kind: kind, label: link.label}]

          _other ->
            []
        end
      end)

    own ++ linked
  end

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

  @doc "The value range of numeric `columns` over every root row, for scaling bars and colours."
  @spec stats(Catalog.t(), Table.t(), [Column.t()], keyword()) ::
          %{String.t() => %{min: term(), max: term()}}
  def stats(%Catalog{} = catalog, %Table{} = root, columns, opts \\ []) do
    plan = Query.plan(catalog, root, columns)
    base = Query.search(plan.query, root, Keyword.get(opts, :search))
    Query.stats(base, plan)
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

  @max_pivot_values 24

  @doc """
  Pivots the grid: one row per distinct value of `rows_column`, one column
  per distinct value of `across_column` (the first #{@max_pivot_values} by
  name, the rest folded into "Other"), each cell the number of root rows
  with both values, plus a total. One GROUP BY statement over the same
  joined plan; `:search` and `:focus` narrow it as they narrow the grid.
  The result's columns are plain component column maps, its rows keyed by
  the row value's text, its stats over every cell so a band or a bar
  scales to the whole pivot.
  """
  @spec pivot(Catalog.t(), Table.t(), Column.t(), Column.t(), keyword()) :: %{
          columns: [map()],
          rows: [%{key: String.t(), cells: %{String.t() => term()}}],
          total_entries: non_neg_integer(),
          stats: %{String.t() => %{min: term(), max: term()}},
          more: non_neg_integer()
        }
  def pivot(%Catalog{} = catalog, %Table{} = root, %Column{} = rows_column, %Column{} = across_column, opts \\ []) do
    focus = Keyword.get(opts, :focus)
    plan = Query.plan(catalog, root, [rows_column, across_column], extra: focus_columns(focus))

    base =
      plan.query
      |> Query.search(root, Keyword.get(opts, :search))
      |> focus_rows(plan, focus)

    triples = Query.pivot_counts(base, plan, rows_column, across_column)

    across_values =
      triples |> Enum.map(&Lens.text(&1.across, across_column)) |> Enum.uniq() |> Enum.sort()

    {shown, folded} = Enum.split(across_values, @max_pivot_values)
    other? = folded != []

    columns =
      Enum.with_index(shown, fn value, index ->
        pivot_column("pv-#{index}", if(value == "", do: "—", else: value), across_column)
      end) ++
        if(other?, do: [pivot_column("pv-other", "Other", across_column)], else: []) ++
        [pivot_column("pv-total", "Total", across_column)]

    index_of = shown |> Enum.with_index() |> Map.new(fn {value, index} -> {value, "pv-#{index}"} end)

    rows =
      triples
      |> Enum.group_by(&Lens.text(&1.rows, rows_column))
      |> Enum.map(fn {row_text, group} ->
        counts =
          Enum.reduce(group, %{}, fn triple, acc ->
            id = Map.get(index_of, Lens.text(triple.across, across_column), "pv-other")
            Map.update(acc, id, triple.count, &(&1 + triple.count))
          end)

        cells =
          columns
          |> Enum.map(& &1.id)
          |> Map.new(fn
            "pv-total" -> {"pv-total", counts |> Map.values() |> Enum.sum()}
            id -> {id, Map.get(counts, id, 0)}
          end)

        %{key: if(row_text == "", do: "—", else: row_text), cells: cells}
      end)
      |> Enum.sort_by(& &1.key)

    values = rows |> Enum.flat_map(&Map.values(&1.cells)) |> Enum.reject(&is_nil/1)
    range = if values == [], do: nil, else: %{min: Enum.min(values), max: Enum.max(values)}

    %{
      columns: columns,
      rows: rows,
      total_entries: length(rows),
      stats: Map.new(columns, &{&1.id, range}),
      more: length(folded)
    }
  end

  defp pivot_column(id, label, %Column{} = across) do
    %{
      id: id,
      spec: id,
      label: "#{across.label}: #{label}",
      short_label: label,
      type: :integer,
      kind: :field,
      lens: :value,
      lenses: [:value, :bar, :band],
      sortable: false,
      removable: false,
      align: :right
    }
  end

  @doc "The largest window `query/4` serves."
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit
end
