defmodule Bilimbi.Base.Grid.Query do
  @moduledoc false

  # Turns resolved columns into one PostgreSQL statement.
  #
  # The root and every table on a path enter the statement as a subquery of
  # the owning module's `Source.query/1`, so each hop carries its owner's
  # tenant, soft-delete and company filters. A one-link is a LEFT JOIN on
  # the target's key. A many-link is a LEFT JOIN to a grouped subquery that
  # already collapsed the reached rows to one per parent key, so the root
  # row count never changes whatever is added, and a rollup with several
  # aggregates over the same link shares one grouped subquery.
  #
  # Bindings are positional atoms (`:root`, `:j1`, `:e1`, `:r1`, `:t1`) and
  # select keys are `:c0`.. by column index, so no atom is ever derived from
  # a path string a person typed.

  import Ecto.Query

  alias Bilimbi.Base.Grid.Catalog
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.Link
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Repo

  @max_columns 400

  @type plan :: %{
          query: Ecto.Query.t(),
          selects: %{Column.t() => Ecto.Query.dynamic_expr()},
          key: Ecto.Query.dynamic_expr(),
          key_column: atom(),
          columns: [Column.t()]
        }

  @doc """
  Builds the joined statement for `columns` on `root`, without select,
  order or paging. `extra:` columns are joined and expressed like the
  others, for a filter to use, but never selected.
  """
  @spec plan(Catalog.t(), Table.t(), [Column.t()], keyword()) :: plan()
  def plan(%Catalog{scope: scope} = catalog, %Table{} = root, selected, opts \\ [])
      when is_list(selected) do
    columns = selected ++ Keyword.get(opts, :extra, [])
    indexed = Enum.with_index(columns)
    trend_indexes = indexes_of(indexed, Keyword.get(opts, :trend, []))

    {delta_indexes, since} =
      case Keyword.get(opts, :delta) do
        {delta_columns, %NaiveDateTime{} = since} -> {indexes_of(indexed, delta_columns), since}
        _none -> {[], nil}
      end

    if length(columns) > @max_columns do
      raise ArgumentError, "a grid holds at most #{@max_columns} columns"
    end

    query = from(r in subquery(root.source.query(scope)), as: :root)

    state = %{
      query: query,
      bindings: %{[] => :root},
      tables: %{[] => root},
      next: 1,
      scope: scope,
      catalog: catalog,
      delta_indexes: delta_indexes,
      since: since
    }

    state =
      columns
      |> Enum.flat_map(&prefixes(&1.hops))
      |> Enum.uniq()
      |> Enum.sort_by(&length/1)
      |> Enum.reduce(state, &join_hop/2)

    {state, rollup_bindings} =
      columns
      |> Enum.with_index()
      |> Enum.filter(fn {column, _index} -> column.kind == :rollup end)
      |> Enum.group_by(fn {column, _index} -> {link_ids(column.hops), column.many.id} end)
      |> Enum.sort_by(fn {group_key, _members} -> group_key end)
      |> Enum.reduce({state, %{}}, &join_rollup/2)

    {state, trend_bindings} =
      indexed
      |> Enum.filter(fn {_column, index} -> index in trend_indexes end)
      |> Enum.reduce({state, %{}}, &join_trend/2)

    selects =
      Map.new(indexed, fn {column, index} ->
        {column, select_expr(column, index, state, rollup_bindings)}
      end)

    key_column = Table.key_field(root).column

    %{
      query: state.query,
      selects: selects,
      key: dynamic([root: r], field(r, ^key_column)),
      key_column: key_column,
      columns: selected,
      trends: Map.new(trend_indexes, &{&1, trend_expr(&1, trend_bindings)}),
      deltas: Map.new(delta_indexes, &{&1, delta_expr(Enum.at(columns, &1), &1, rollup_bindings)})
    }
  end

  defp indexes_of(indexed, wanted) do
    for {column, index} <- indexed, column in wanted, column.kind == :rollup, do: index
  end

  @doc """
  Restricts the rows to the one record a workspace selection named:
  `:root` for the root's own key, or a column whose value is the key of
  the selected table, reached through one-links.
  """
  @spec focus(Ecto.Query.t(), plan(), :root | Column.t(), term()) :: Ecto.Query.t()
  def focus(query, %{key_column: key_column}, :root, id) do
    where(query, [root: r], field(r, ^key_column) == ^id)
  end

  def focus(query, %{selects: selects}, %Column{} = column, id) do
    expr = Map.fetch!(selects, column)
    where(query, ^dynamic([], ^expr == ^id))
  end

  defp prefixes(hops) do
    for n <- 1..length(hops)//1, do: Enum.take(hops, n)
  end

  defp link_ids(links), do: Enum.map(links, & &1.id)

  # One LEFT JOIN per distinct one-link prefix, parent binding first.
  defp join_hop(hops, state) do
    path = link_ids(hops)
    parent_path = Enum.drop(path, -1)
    parent = Map.fetch!(state.bindings, parent_path)
    parent_table = Map.fetch!(state.tables, parent_path)
    %Link{} = link = List.last(hops)
    target = target_table!(link, state)
    binding = :"j#{state.next}"

    query =
      join_one(
        state.query,
        link,
        parent,
        parent_table,
        target,
        binding,
        :"e#{state.next}",
        state.scope
      )

    %{
      state
      | query: query,
        bindings: Map.put(state.bindings, path, binding),
        tables: Map.put(state.tables, path, target),
        next: state.next + 1
    }
  end

  defp join_one(
         query,
         %Link{on: {from_field, to_field}},
         parent,
         parent_table,
         target,
         binding,
         _edge,
         scope
       ) do
    from_column = Map.fetch!(parent_table.fields, from_field).column
    to_column = Map.fetch!(target.fields, to_field).column

    join(query, :left, [{^parent, p}], t in subquery(target.source.query(scope)),
      as: ^binding,
      on: field(p, ^from_column) == field(t, ^to_column)
    )
  end

  defp join_one(
         query,
         %Link{via: {module, function}},
         parent,
         parent_table,
         target,
         binding,
         edge,
         scope
       ) do
    parent_key = Table.key_field(parent_table).column
    target_key = Table.key_field(target).column

    query
    |> join(:left, [{^parent, p}], e in subquery(apply(module, function, [scope])),
      as: ^edge,
      on: field(p, ^parent_key) == e.from_key
    )
    |> join(:left, [{^edge, e}], t in subquery(target.source.query(scope)),
      as: ^binding,
      on: e.to_key == field(t, ^target_key)
    )
  end

  # One grouped subquery per (prefix, many-link): every aggregate over that
  # link is a key of its select, and the outer join reads them by column index.
  defp join_rollup({{hop_ids, _many_id}, members}, {state, rollup_bindings}) do
    {%Column{} = first, _index} = hd(members)
    parent = Map.fetch!(state.bindings, hop_ids)
    parent_table = Map.fetch!(state.tables, hop_ids)
    %Link{} = many = first.many
    target = target_table!(many, state)
    binding = :"r#{state.next}"

    {inner, key_expr, inner_state} =
      rollup_base(many, parent_table, target, state.scope, state.catalog)

    {inner, inner_state} =
      members
      |> Enum.flat_map(fn {column, _index} -> prefixes(column.tail) end)
      |> Enum.uniq()
      |> Enum.sort_by(&length/1)
      |> Enum.reduce({inner, inner_state}, &join_tail/2)

    aggregates =
      Map.new(members, fn {column, index} ->
        {:"c#{index}", aggregate_expr(column, inner_state)}
      end)

    # A change-since-a-date lens wants the same aggregate over the rows
    # that already existed at the date: the aggregate with a FILTER, in
    # the same grouped subquery, so the two never disagree.
    aggregates =
      Enum.reduce(members, aggregates, fn {column, index}, acc ->
        if index in state.delta_indexes and target.time_field,
          do:
            Map.put(acc, :"d#{index}", aggregate_before(column, inner_state, target, state.since)),
          else: acc
      end)

    inner =
      inner
      |> group_by(^[key_expr])
      |> select(^%{key: key_expr})
      |> select_merge(^aggregates)

    parent_join_column =
      case many.on do
        {from_field, _to_field} -> Map.fetch!(parent_table.fields, from_field).column
        nil -> Table.key_field(parent_table).column
      end

    query =
      join(state.query, :left, [{^parent, p}], r in subquery(inner),
        as: ^binding,
        on: field(p, ^parent_join_column) == r.key
      )

    rollup_bindings =
      Enum.reduce(members, rollup_bindings, fn {_column, index}, acc ->
        Map.put(acc, index, binding)
      end)

    {%{state | query: query, next: state.next + 1}, rollup_bindings}
  end

  # The rollup's own rows: the many-link's target, keyed by the parent it
  # belongs to. Inside the subquery the target is `:t0` and tail hops are `:t1`..
  defp rollup_base(%Link{on: {_from_field, to_field}}, _parent_table, target, scope, catalog) do
    to_column = Map.fetch!(target.fields, to_field).column
    inner = from(t in subquery(target.source.query(scope)), as: :t0)
    key = dynamic([t0: t], field(t, ^to_column))

    {inner, key,
     %{bindings: %{[] => :t0}, tables: %{[] => target}, next: 1, scope: scope, catalog: catalog}}
  end

  defp rollup_base(%Link{via: {module, function}}, _parent_table, target, scope, catalog) do
    target_key = Table.key_field(target).column

    inner =
      from(e in subquery(apply(module, function, [scope])), as: :edge)
      |> join(:inner, [edge: e], t in subquery(target.source.query(scope)),
        as: :t0,
        on: e.to_key == field(t, ^target_key)
      )

    key = dynamic([edge: e], e.from_key)

    {inner, key,
     %{bindings: %{[] => :t0}, tables: %{[] => target}, next: 1, scope: scope, catalog: catalog}}
  end

  defp join_tail(links, {inner, state}) do
    path = link_ids(links)
    parent_path = Enum.drop(path, -1)
    parent = Map.fetch!(state.bindings, parent_path)
    parent_table = Map.fetch!(state.tables, parent_path)
    %Link{} = link = List.last(links)
    target = target_table!(link, state)
    binding = :"t#{state.next}"

    inner =
      join_one(
        inner,
        link,
        parent,
        parent_table,
        target,
        binding,
        :"te#{state.next}",
        state.scope
      )

    {inner,
     %{
       state
       | bindings: Map.put(state.bindings, path, binding),
         tables: Map.put(state.tables, path, target),
         next: state.next + 1
     }}
  end

  defp aggregate_expr(%Column{agg: :count}, inner_state) do
    target = Map.fetch!(inner_state.tables, [])
    key = Table.key_field(target).column
    dynamic([t0: t], count(field(t, ^key)))
  end

  defp aggregate_expr(%Column{agg: agg, field: field, tail: tail}, inner_state) do
    binding = Map.fetch!(inner_state.bindings, link_ids(tail))
    table = Map.fetch!(inner_state.tables, link_ids(tail))
    column = field.column

    case agg do
      :sum ->
        dynamic([{^binding, t}], sum(field(t, ^column)))

      :avg ->
        dynamic([{^binding, t}], avg(field(t, ^column)))

      :min ->
        dynamic([{^binding, t}], min(field(t, ^column)))

      :max ->
        dynamic([{^binding, t}], max(field(t, ^column)))

      :list ->
        dynamic(
          [{^binding, t}],
          fragment(
            "left(string_agg(DISTINCT ?::text, ', ' ORDER BY ?::text), 300)",
            field(t, ^column),
            field(t, ^column)
          )
        )

      :latest ->
        time_column = Map.fetch!(table.fields, table.time_field).column

        dynamic(
          [{^binding, t}],
          fragment(
            "(array_agg(? ORDER BY ? DESC NULLS LAST))[1]",
            field(t, ^column),
            field(t, ^time_column)
          )
        )
    end
  end

  # The aggregate as it stood at `since`: only rows the target dated before it.
  defp aggregate_before(%Column{agg: :count}, _inner_state, target, since) do
    key = Table.key_field(target).column
    time = Map.fetch!(target.fields, target.time_field).column
    dynamic([t0: t], count(field(t, ^key)) |> filter(field(t, ^time) < ^since))
  end

  defp aggregate_before(%Column{agg: :sum, field: field, tail: tail}, inner_state, target, since) do
    binding = Map.fetch!(inner_state.bindings, link_ids(tail))
    column = field.column
    time = Map.fetch!(target.fields, target.time_field).column

    dynamic(
      [{^binding, t}, t0: t0],
      sum(field(t, ^column)) |> filter(field(t0, ^time) < ^since)
    )
  end

  defp aggregate_before(%Column{agg: agg}, _inner_state, _target, _since),
    do: raise(ArgumentError, "a change since a date is only known for count and sum, not #{agg}")

  # A trend is the same aggregate per calendar month over the last twelve:
  # a subquery grouped by parent key and month, folded into two ordered
  # arrays per parent, joined like a rollup.
  defp join_trend({%Column{kind: :rollup, agg: agg} = column, index}, {state, trend_bindings})
       when agg in [:count, :sum] do
    hop_ids = link_ids(column.hops)
    parent = Map.fetch!(state.bindings, hop_ids)
    parent_table = Map.fetch!(state.tables, hop_ids)
    %Link{} = many = column.many
    target = target_table!(many, state)

    case target.time_field do
      nil ->
        {state, trend_bindings}

      time_field ->
        time = Map.fetch!(target.fields, time_field).column
        binding = :"s#{state.next}"

        {inner, key_expr, inner_state} =
          rollup_base(many, parent_table, target, state.scope, state.catalog)

        {inner, inner_state} =
          column.tail
          |> prefixes()
          |> Enum.sort_by(&length/1)
          |> Enum.reduce({inner, inner_state}, &join_tail/2)

        start = NaiveDateTime.new!(months_ago(12), ~T[00:00:00])
        month = dynamic([t0: t], fragment("date_trunc('month', ?)", field(t, ^time)))
        value = aggregate_expr(column, inner_state)

        by_month =
          inner
          |> where([t0: t], field(t, ^time) >= ^start)
          |> group_by(^[key_expr, month])
          |> select(^%{key: key_expr, month: month, value: value})

        folded =
          from(s in subquery(by_month),
            group_by: s.key,
            select: %{
              key: s.key,
              months: fragment("array_agg(? ORDER BY ?)", s.month, s.month),
              values: fragment("array_agg(?::float ORDER BY ?)", s.value, s.month)
            }
          )

        parent_join_column =
          case many.on do
            {from_field, _to_field} -> Map.fetch!(parent_table.fields, from_field).column
            nil -> Table.key_field(parent_table).column
          end

        query =
          join(state.query, :left, [{^parent, p}], s in subquery(folded),
            as: ^binding,
            on: field(p, ^parent_join_column) == s.key
          )

        {%{state | query: query, next: state.next + 1}, Map.put(trend_bindings, index, binding)}
    end
  end

  defp join_trend(_other, acc), do: acc

  defp trend_expr(index, trend_bindings) do
    case Map.fetch(trend_bindings, index) do
      {:ok, binding} -> {dynamic([{^binding, s}], s.months), dynamic([{^binding, s}], s.values)}
      :error -> nil
    end
  end

  defp delta_expr(%Column{agg: :count}, index, rollups) do
    binding = Map.fetch!(rollups, index)
    name = :"d#{index}"
    dynamic([{^binding, r}], coalesce(field(r, ^name), 0))
  end

  defp delta_expr(%Column{}, index, rollups) do
    binding = Map.fetch!(rollups, index)
    name = :"d#{index}"
    dynamic([{^binding, r}], field(r, ^name))
  end

  @doc "The first day of the month `count` months before this one."
  @spec months_ago(non_neg_integer()) :: Date.t()
  def months_ago(count) do
    today = Date.utc_today()
    total = today.year * 12 + (today.month - 1) - count
    Date.new!(div(total, 12), rem(total, 12) + 1, 1)
  end

  @doc "The last twelve calendar months, oldest first, as `{year, month}` pairs."
  @spec trend_months() :: [{pos_integer(), pos_integer()}]
  def trend_months do
    for i <- 11..0//-1 do
      date = months_ago(i)
      {date.year, date.month}
    end
  end

  defp select_expr(%Column{kind: :field} = column, _index, state, _rollups) do
    binding = Map.fetch!(state.bindings, link_ids(column.hops))
    dynamic([{^binding, t}], field(t, ^column.field.column))
  end

  # A parent with no reached rows has no group row, so a LEFT JOIN yields
  # NULL; a count of nothing is 0, and reads, sorts and colours as one.
  defp select_expr(%Column{kind: :rollup, agg: :count}, index, _state, rollups) do
    binding = Map.fetch!(rollups, index)
    name = :"c#{index}"
    dynamic([{^binding, r}], coalesce(field(r, ^name), 0))
  end

  defp select_expr(%Column{kind: :rollup}, index, _state, rollups) do
    binding = Map.fetch!(rollups, index)
    name = :"c#{index}"
    dynamic([{^binding, r}], field(r, ^name))
  end

  # Columns were resolved against this catalog, so every link target is in it.
  defp target_table!(%Link{to: to}, %{catalog: catalog}) do
    case Catalog.fetch_table(catalog, to) do
      {:ok, table} ->
        table

      :error ->
        raise ArgumentError, "grid link points at a table outside the catalog: #{inspect(to)}"
    end
  end

  @doc "`query` (the plan's statement, perhaps filtered) selecting the key and every column by index."
  @spec select_rows(Ecto.Query.t(), plan()) :: Ecto.Query.t()
  def select_rows(query, %{selects: selects, key: key, columns: columns} = plan) do
    cells =
      columns
      |> Enum.with_index()
      |> Map.new(fn {column, index} -> {:"c#{index}", Map.fetch!(selects, column)} end)

    extras =
      Enum.reduce(Map.get(plan, :trends, %{}), %{}, fn
        {index, {months, values}}, acc ->
          acc |> Map.put(:"m#{index}", months) |> Map.put(:"v#{index}", values)

        {_index, nil}, acc ->
          acc
      end)

    extras =
      Enum.reduce(Map.get(plan, :deltas, %{}), extras, fn {index, expr}, acc ->
        Map.put(acc, :"d#{index}", expr)
      end)

    query
    |> select(^%{key: key})
    |> select_merge(^cells)
    |> select_merge(^extras)
  end

  @doc "Orders by a column, or by the key when `column` is nil, always tie-broken by key."
  @spec order(Ecto.Query.t(), plan(), Column.t() | nil, :asc | :desc) :: Ecto.Query.t()
  def order(query, %{key: key}, nil, dir), do: order_by(query, ^[{dir, key}])

  def order(query, %{key: key, selects: selects}, %Column{} = column, dir) do
    expr = Map.fetch!(selects, column)
    nulls = if dir == :asc, do: :asc_nulls_last, else: :desc_nulls_last
    order_by(query, ^[{nulls, expr}, {:asc, key}])
  end

  @doc "Restricts the rows to those whose searchable root fields contain `text`."
  @spec search(Ecto.Query.t(), Table.t(), String.t()) :: Ecto.Query.t()
  def search(query, %Table{}, text) when text in [nil, ""], do: query

  def search(query, %Table{} = root, text) when is_binary(text) do
    pattern = "%" <> escape_like(text) <> "%"

    condition =
      root
      |> Catalog.search_fields()
      |> Enum.reduce(nil, fn field, acc ->
        column = field.column
        match = dynamic([root: r], ilike(fragment("?::text", field(r, ^column)), ^pattern))
        if acc, do: dynamic([], ^acc or ^match), else: match
      end)

    case condition do
      nil -> where(query, false)
      _dynamic -> where(query, ^condition)
    end
  end

  defp escape_like(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc "Restricts the plan to the root rows with these keys."
  @spec with_keys(Ecto.Query.t(), plan(), [term()]) :: Ecto.Query.t()
  def with_keys(query, %{key_column: key_column}, keys) when is_list(keys) do
    where(query, [root: r], field(r, ^key_column) in ^keys)
  end

  @doc "How many root rows the statement yields."
  @spec count(Ecto.Query.t(), plan()) :: non_neg_integer()
  def count(query, %{key: key}) do
    inner =
      query |> exclude(:order_by) |> exclude(:limit) |> exclude(:offset) |> select(^%{key: key})

    Repo.one(from(s in subquery(inner), select: count()))
  end

  @doc "Per numeric column, the smallest and largest value across the statement's rows."
  @spec stats(Ecto.Query.t(), plan()) :: %{String.t() => %{min: term(), max: term()}}
  def stats(query, %{selects: selects, columns: columns}) do
    numeric =
      columns
      |> Enum.with_index()
      |> Enum.filter(fn {column, _index} -> Column.numeric?(column) end)

    if numeric == [] do
      %{}
    else
      aggregates =
        Enum.reduce(numeric, %{}, fn {column, index}, acc ->
          expr = Map.fetch!(selects, column)

          acc
          |> Map.put(:"min#{index}", dynamic([], min(^expr)))
          |> Map.put(:"max#{index}", dynamic([], max(^expr)))
        end)

      row =
        query
        |> exclude(:order_by)
        |> exclude(:limit)
        |> exclude(:offset)
        |> select(%{})
        |> select_merge(^aggregates)
        |> Repo.one()

      Map.new(numeric, fn {column, index} ->
        {column.id, %{min: Map.get(row, :"min#{index}"), max: Map.get(row, :"max#{index}")}}
      end)
    end
  end

  @doc "The root rows counted per pair of values of two columns, in one GROUP BY."
  @spec pivot_counts(Ecto.Query.t(), plan(), Column.t(), Column.t()) ::
          [%{rows: term(), across: term(), count: non_neg_integer()}]
  def pivot_counts(query, %{selects: selects, key_column: key_column}, rows_column, across_column) do
    rows_expr = Map.fetch!(selects, rows_column)
    across_expr = Map.fetch!(selects, across_column)

    query
    |> exclude(:order_by)
    |> exclude(:limit)
    |> exclude(:offset)
    |> group_by(^[rows_expr, across_expr])
    |> select(^%{rows: rows_expr, across: across_expr})
    |> select_merge([root: r], %{count: count(field(r, ^key_column))})
    |> Repo.all()
  end

  @doc "PostgreSQL's estimated total cost for the statement, from EXPLAIN."
  @spec estimated_cost(Ecto.Query.t()) :: float() | nil
  def estimated_cost(query) do
    case Repo.explain(:all, query) do
      plan when is_binary(plan) ->
        case Regex.run(~r/cost=\d+(?:\.\d+)?\.\.(\d+(?:\.\d+)?)/, plan) do
          [_all, total] -> String.to_float(ensure_float(total))
          nil -> nil
        end

      _other ->
        nil
    end
  end

  defp ensure_float(text), do: if(String.contains?(text, "."), do: text, else: text <> ".0")

  @doc """
  Turns selected maps into rows of `%{key, cells, series, before}` keyed by
  column id: `series` the trend of the last twelve months for the trend
  columns, `before` the aggregate as of the date for the delta columns.
  """
  @spec rows([map()], plan()) :: [
          %{key: term(), cells: %{String.t() => term()}, series: map(), before: map()}
        ]
  def rows(selected, %{columns: columns} = plan) do
    indexed = Enum.with_index(columns)
    trends = plan |> Map.get(:trends, %{}) |> Enum.reject(fn {_index, expr} -> is_nil(expr) end)
    deltas = Map.get(plan, :deltas, %{})
    months = trend_months()

    Enum.map(selected, fn row ->
      cells = Map.new(indexed, fn {column, index} -> {column.id, Map.get(row, :"c#{index}")} end)

      series =
        Map.new(trends, fn {index, _expr} ->
          {Enum.at(columns, index).id,
           series(months, Map.get(row, :"m#{index}"), Map.get(row, :"v#{index}"))}
        end)

      before =
        Map.new(deltas, fn {index, _expr} ->
          {Enum.at(columns, index).id, Map.get(row, :"d#{index}")}
        end)

      %{key: row.key, cells: cells, series: series, before: before}
    end)
  end

  # The twelve months in order, a month with no rows counting zero.
  defp series(months, db_months, db_values) when is_list(db_months) and is_list(db_values) do
    lookup =
      db_months
      |> Enum.zip(db_values)
      |> Map.new(fn {month, value} -> {{month.year, month.month}, value * 1.0} end)

    Enum.map(months, &Map.get(lookup, &1, 0.0))
  end

  defp series(months, _db_months, _db_values), do: Enum.map(months, fn _month -> 0.0 end)
end
