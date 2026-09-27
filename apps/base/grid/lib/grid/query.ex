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
      catalog: catalog
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

    selects =
      columns
      |> Enum.with_index()
      |> Map.new(fn {column, index} ->
        {column, select_expr(column, index, state, rollup_bindings)}
      end)

    key_column = Table.key_field(root).column

    %{
      query: state.query,
      selects: selects,
      key: dynamic([root: r], field(r, ^key_column)),
      key_column: key_column,
      columns: selected
    }
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
  def select_rows(query, %{selects: selects, key: key, columns: columns}) do
    cells =
      columns
      |> Enum.with_index()
      |> Map.new(fn {column, index} -> {:"c#{index}", Map.fetch!(selects, column)} end)

    query
    |> select(^%{key: key})
    |> select_merge(^cells)
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

  @doc "Turns selected maps into rows of `%{key, cells}` keyed by column id."
  @spec rows([map()], [Column.t()]) :: [%{key: term(), cells: %{String.t() => term()}}]
  def rows(selected, columns) do
    indexed = Enum.with_index(columns)

    Enum.map(selected, fn row ->
      cells = Map.new(indexed, fn {column, index} -> {column.id, Map.get(row, :"c#{index}")} end)
      %{key: row.key, cells: cells}
    end)
  end
end
