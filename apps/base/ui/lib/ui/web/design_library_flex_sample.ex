defmodule Bilimbi.Base.UI.Web.DesignLibraryFlexSample do
  @moduledoc false

  # The Design Library's host for `flex_table/1`: a fixed synthetic set of
  # example companies, wide enough for the carpet to mean something, and the
  # component's operations applied to plain assigns. There is no catalog
  # behind it, so the add bar offers the three columns the set holds back,
  # and a rollup expands to the lines the set carries for that row. Nothing
  # is simulated: every gesture changes what the specimen shows.

  @rows 400
  @regions ~w(North South East West Central)
  @statuses ~w(active pending suspended)

  @columns [
    %{
      id: "name",
      spec: "name",
      label: "Name",
      short_label: "Name",
      type: :string,
      kind: :slot,
      lens: :value,
      lenses: [:value, :band],
      sortable: true,
      removable: false,
      align: nil
    },
    %{
      id: "code",
      spec: "code",
      label: "Code",
      short_label: "Code",
      type: :string,
      kind: :field,
      lens: :value,
      lenses: [:value, :band],
      sortable: true,
      removable: true,
      align: nil
    },
    %{
      id: "status",
      spec: "status",
      label: "Status",
      short_label: "Status",
      type: :enum,
      kind: :field,
      lens: :band,
      lenses: [:value, :band],
      sortable: true,
      removable: true,
      align: nil
    },
    %{
      id: "region",
      spec: "region",
      label: "Region",
      short_label: "Region",
      type: :enum,
      kind: :field,
      lens: :value,
      lenses: [:value, :band],
      sortable: true,
      removable: true,
      align: nil
    },
    %{
      id: "employees_count",
      spec: "employees:count",
      label: "Employees › Count",
      short_label: "Count",
      type: :integer,
      kind: :rollup,
      lens: :bar,
      lenses: [:value, :bar, :band],
      sortable: true,
      removable: true,
      align: :right
    },
    %{
      id: "orders-amount_sum",
      spec: "orders.amount:sum",
      label: "Orders › Amount (Sum)",
      short_label: "Amount (Sum)",
      type: :decimal,
      kind: :rollup,
      lens: :band,
      lenses: [:value, :bar, :band],
      sortable: true,
      removable: true,
      align: :right
    },
    %{
      id: "updated_at",
      spec: "updated_at",
      label: "Updated",
      short_label: "Updated",
      type: :datetime,
      kind: :field,
      lens: :value,
      lenses: [:value, :band],
      sortable: true,
      removable: true,
      align: :right
    }
  ]

  @extra [
    %{
      id: "users_count",
      spec: "users:count",
      label: "Users › Count",
      short_label: "Count",
      type: :integer,
      kind: :rollup,
      lens: :value,
      lenses: [:value, :bar, :band],
      sortable: true,
      removable: true,
      align: :right
    },
    %{
      id: "parent-name",
      spec: "parent.name",
      label: "Parent company › Name",
      short_label: "Name",
      type: :string,
      kind: :field,
      lens: :value,
      lenses: [:value, :band],
      sortable: true,
      removable: true,
      align: nil
    },
    %{
      id: "addresses_count",
      spec: "addresses:count",
      label: "Addresses › Count",
      short_label: "Count",
      type: :integer,
      kind: :rollup,
      lens: :value,
      lenses: [:value, :bar, :band],
      sortable: true,
      removable: true,
      align: :right
    }
  ]

  @doc "The specimen's starting state."
  def initial do
    %{
      columns: @columns,
      sort_by: "region",
      sort_dir: :asc,
      zoom: 28,
      suggestions: [],
      add_query: "",
      expanded: %{}
    }
  end

  @doc "The columns the add bar can still offer."
  def extra, do: @extra

  @doc "Every row of the set, with cells prepared for the given columns."
  def rows(state, limit \\ @rows, offset \\ 0) do
    all_columns = @columns ++ @extra
    stats = stats(all_columns)

    values()
    |> sort(state.sort_by, state.sort_dir)
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(fn row ->
      cells =
        Map.new(state.columns, fn column ->
          value = Map.fetch!(row, column.id)
          {column.id, cell(value, column, Map.get(stats, column.id))}
        end)

      %{key: row.id, cells: cells}
    end)
  end

  @doc "The window payload the hook draws in a canvas mode."
  def window(state, offset, limit) do
    rows =
      state
      |> rows(limit, offset)
      |> Enum.map(fn row ->
        [
          row.key,
          Enum.map(state.columns, fn column ->
            cell = Map.fetch!(row.cells, column.id)
            [cell.text, cell.n, cell.band, cell.scale, nil]
          end)
        ]
      end)

    %{offset: offset, total: @rows, rows: rows}
  end

  @doc "How many rows the set holds."
  def total, do: @rows

  @doc "Applies one component op to the specimen's state."
  def apply(%{"op" => "remove", "spec" => spec}, state) do
    %{
      state
      | columns: Enum.reject(state.columns, &(&1.spec == spec and &1.removable)),
        sort_by: if(state.sort_by == spec, do: "name", else: state.sort_by)
    }
  end

  def apply(%{"op" => "add", "spec" => spec}, state), do: add(state, spec)

  def apply(%{"op" => "add_typed", "add" => text}, state) do
    case suggest(text, state) do
      [first | _rest] -> add(state, first.spec)
      [] -> state
    end
  end

  def apply(%{"op" => "suggest", "add" => text}, state) do
    %{state | add_query: text, suggestions: if(text == "", do: [], else: suggest(text, state))}
  end

  def apply(%{"op" => "move", "spec" => spec} = params, state) do
    before = params["before"]
    moving = Enum.find(state.columns, &(&1.spec == spec))
    rest = Enum.reject(state.columns, &(&1.spec == spec))

    columns =
      case {moving, before && Enum.find_index(rest, &(&1.spec == before))} do
        {nil, _index} -> state.columns
        {column, nil} -> rest ++ [column]
        {column, index} -> List.insert_at(rest, index, column)
      end

    %{state | columns: columns}
  end

  def apply(%{"op" => "lens", "spec" => spec, "lens" => lens}, state) do
    columns =
      Enum.map(state.columns, fn column ->
        with true <- column.spec == spec,
             lens when not is_nil(lens) <- Enum.find(column.lenses, &(Atom.to_string(&1) == lens)) do
          %{column | lens: lens}
        else
          _other -> column
        end
      end)

    %{state | columns: columns}
  end

  def apply(%{"op" => "sort", "sort" => spec}, %{sort_by: spec, sort_dir: :asc} = state),
    do: %{state | sort_dir: :desc}

  def apply(%{"op" => "sort", "sort" => spec}, state),
    do: %{state | sort_by: spec, sort_dir: :asc}

  def apply(%{"op" => "zoom", "dir" => "in"}, state),
    do: %{state | zoom: min(state.zoom + step(state.zoom), 40)}

  def apply(%{"op" => "zoom", "dir" => "out"}, state),
    do: %{state | zoom: max(state.zoom - step(state.zoom), 2)}

  def apply(%{"op" => "zoom_preset", "z" => z}, state) do
    case Integer.parse(to_string(z)) do
      {zoom, ""} -> %{state | zoom: zoom |> max(2) |> min(40)}
      _other -> state
    end
  end

  def apply(%{"op" => "zoom_rect"} = params, state) do
    rows = max(int(params["to_row"]) - int(params["from_row"]), 1)
    height = max(int(params["height"]), 100)
    %{state | zoom: (height / rows) |> trunc() |> max(2) |> min(40)}
  end

  def apply(%{"op" => "expand", "spec" => spec, "key" => key}, state) do
    with {id, ""} <- Integer.parse(to_string(key)),
         %{} = column <- Enum.find(state.columns, &(&1.spec == spec and &1.kind == :rollup)) do
      lines = lines(id, column.id)

      %{
        state
        | expanded:
            Map.update(state.expanded, id, %{column.id => lines}, &Map.put(&1, column.id, lines))
      }
    else
      _other -> state
    end
  end

  def apply(%{"op" => "collapse", "spec" => spec, "key" => key}, state) do
    with {id, ""} <- Integer.parse(to_string(key)),
         %{} = column <- Enum.find(state.columns, &(&1.spec == spec)) do
      %{state | expanded: Map.update(state.expanded, id, %{}, &Map.delete(&1, column.id))}
    else
      _other -> state
    end
  end

  def apply(_params, state), do: state

  @doc "The mode a zoom falls in, by the same bands the grid page uses."
  def mode(zoom) when zoom <= 6, do: :carpet
  def mode(zoom) when zoom <= 20, do: :mid
  def mode(_zoom), do: :full

  defp add(state, spec) do
    case Enum.find(@extra, &(&1.spec == spec)) do
      nil ->
        state

      column ->
        if Enum.any?(state.columns, &(&1.spec == spec)),
          do: state,
          else: %{state | columns: state.columns ++ [column], suggestions: [], add_query: ""}
    end
  end

  defp suggest(text, state) do
    shown = Enum.map(state.columns, & &1.spec)
    down = String.downcase(text)

    @extra
    |> Enum.reject(&(&1.spec in shown))
    |> Enum.filter(
      &(down == "" or String.contains?(String.downcase(&1.label <> " " <> &1.spec), down))
    )
  end

  defp step(zoom) when zoom < 8, do: 1
  defp step(zoom) when zoom < 20, do: 2
  defp step(_zoom), do: 4

  defp int(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> integer
      _other -> 0
    end
  end

  # Deterministic values: the same set on every mount, spread enough that
  # every band appears.
  defp values do
    for id <- 1..@rows do
      %{
        id: id,
        name: "Example Company #{id}",
        code: "example-#{id}",
        status: Enum.at(@statuses, rem(id * 7, 3)),
        region: Enum.at(@regions, rem(id * 3, 5)),
        employees_count: rem(id * 37, 250),
        "orders-amount_sum": rem(id * 7919, 100_000) / 100,
        updated_at: NaiveDateTime.add(~N[2026-08-14 12:00:00], -rem(id * 13, 400), :day),
        users_count: rem(id * 11, 40),
        "parent-name": if(rem(id, 4) == 0, do: "Example Company #{div(id, 4)}"),
        addresses_count: rem(id, 5)
      }
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put(:id, id)
    end
  end

  defp lines(id, "employees_count") do
    for n <- 1..min(rem(id * 37, 250), 5)//1,
        do: %{"name" => "Person #{id}-#{n}", "status" => Enum.at(~w(active probation), rem(n, 2))}
  end

  defp lines(id, _column_id) do
    for n <- 1..min(rem(id, 4) + 1, 4)//1,
        do: %{
          "reference" => "ORD-#{id}-#{n}",
          "amount" => Integer.to_string(rem(id * n * 977, 20_000))
        }
  end

  defp sort(rows, spec, dir) do
    column = Enum.find(@columns ++ @extra, &(&1.spec == spec)) || hd(@columns)
    sorted = Enum.sort_by(rows, &sort_key(Map.fetch!(&1, column.id)))
    if dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp sort_key(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)
  defp sort_key(nil), do: ""
  defp sort_key(other), do: other

  defp stats(columns) do
    rows = values()

    Map.new(columns, fn column ->
      numbers =
        rows
        |> Enum.map(&Map.fetch!(&1, column.id))
        |> Enum.map(&number/1)
        |> Enum.reject(&is_nil/1)

      {column.id,
       if(numbers == [], do: nil, else: %{min: Enum.min(numbers), max: Enum.max(numbers)})}
    end)
  end

  defp number(value) when is_number(value), do: value * 1.0

  defp number(%NaiveDateTime{} = naive),
    do: NaiveDateTime.diff(naive, ~N[1970-01-01 00:00:00]) * 1.0

  defp number(_other), do: nil

  defp cell(nil, _column, _stats),
    do: %{text: "", value: nil, n: nil, band: nil, scale: nil, series: nil, delta: nil}

  defp cell(value, column, stats) do
    {n, scale} =
      cond do
        column.type in [:integer, :float, :decimal, :datetime, :date] and is_map(stats) ->
          v = number(value)
          span = stats.max - stats.min
          {if(span == 0, do: 0.5, else: (v - stats.min) / span), :sequential}

        true ->
          {:erlang.phash2(to_string(value), 8) / 7, :categorical}
      end

    band = if scale == :sequential, do: min(trunc(n * 5), 4), else: round(n * 7)
    %{text: text(value), value: value, n: n, band: band, scale: scale, series: nil, delta: nil}
  end

  defp text(float) when is_float(float), do: :erlang.float_to_binary(float, decimals: 2)
  defp text(%NaiveDateTime{} = naive), do: naive |> NaiveDateTime.to_date() |> Date.to_iso8601()
  defp text(other), do: to_string(other)
end
