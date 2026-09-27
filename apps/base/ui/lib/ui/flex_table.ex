defmodule Bilimbi.Base.UI.FlexTable do
  @moduledoc """
  The plain data `Bilimbi.Base.UI.Components.flex_table/1` takes, and the
  small pure helpers it renders with.

  The component is presentation only: it knows nothing about catalogs,
  links or queries. A host (the grid page, or a list page that lets people
  add walked columns) hands it columns and prepared cells in these shapes
  and handles the one event it pushes.

  ## Columns

      %{
        id: "company-name",         # DOM-safe, unique in the table
        spec: "company.name",       # what the host's event handlers get back
        label: "Company › Name",    # full path label, the tooltip
        short_label: "Name",        # what the header shows
        type: :string,              # :integer | :float | :decimal | :string | :boolean | :date | :datetime | :enum
        kind: :field,               # :field | :rollup | :slot
        lens: :value,               # :value | :bar | :band | :trend
        lenses: [:value, :band],    # the lenses this column allows
        sortable: true,
        removable: true,
        align: nil                  # or :right
      }

  A `:slot` column is drawn in the full table by the caller's `<:col>` of
  the same `id`; the other kinds are drawn from their cells. Every kind is
  drawn from its cell in the compact and carpet modes, so a slot column
  needs a cell too if it is to appear there.

  ## Cells

  `rows` is a list of `%{key: term, cells: %{column_id => cell}}`, where a
  cell is `%{text, value, n, band, scale}`: the text to show, the raw
  value, its 0..1 position within the column's range or nil, the band that
  position falls in, and whether the scale is `:sequential`, `:categorical`
  or `:binary`.

  ## Events

  Everything the component does is one event, `event` (default `"grid"`),
  with an `op`: `add`, `add_typed`, `suggest`, `remove`, `move`, `lens`,
  `sort`, `zoom`, `zoom_preset`, `zoom_rect`, `expand`, `collapse`,
  `group`, `window`, `cell`. The hook pushes `move`, `group`, `zoom`,
  `zoom_rect`, `window` and `cell`; the markup pushes the rest.
  """

  @modes [:carpet, :mid, :full]

  @doc "The drawing modes, from most to least compact."
  @spec modes() :: [atom()]
  def modes, do: @modes

  @doc "Whether the mode draws on a canvas rather than into a table."
  @spec canvas?(atom()) :: boolean()
  def canvas?(mode), do: mode in [:carpet, :mid]

  @doc "The columns as the hook reads them, one JSON string."
  @spec columns_json([map()]) :: String.t()
  def columns_json(columns) when is_list(columns) do
    columns
    |> Enum.map(fn column ->
      %{
        id: column.id,
        spec: column.spec,
        label: column.label,
        short: column.short_label,
        type: column.type,
        kind: column.kind,
        lens: Map.get(column, :lens, :value),
        numeric: column.type in [:integer, :float, :decimal, :date, :datetime]
      }
    end)
    |> JSON.encode!()
  end

  @doc "The word a mode is called."
  @spec mode_label(atom()) :: String.t()
  def mode_label(:carpet), do: "Carpet"
  def mode_label(:mid), do: "Compact"
  def mode_label(:full), do: "Table"

  @doc "The word a lens is called."
  @spec lens_label(atom()) :: String.t()
  def lens_label(:value), do: "Value"
  def lens_label(:bar), do: "Bar"
  def lens_label(:band), do: "Colour band"
  def lens_label(:trend), do: "Trend"
  def lens_label(:delta), do: "Change since a date"

  @doc """
  Splits rows into runs that share the grouped column's text, in the order
  given: a host sorts by the grouped column, so a run is a group. With no
  group, or a group no column matches, one run with no label holds every
  row.
  """
  @spec groups([map()], [map()], String.t() | nil) :: [%{label: String.t() | nil, rows: [map()]}]
  def groups(rows, _columns, nil), do: [%{label: nil, rows: rows}]

  def groups(rows, columns, group) when is_list(rows) and is_binary(group) do
    case Enum.find(columns, &(&1.spec == group)) do
      nil ->
        [%{label: nil, rows: rows}]

      column ->
        rows
        |> Enum.chunk_by(&group_text(&1, column.id))
        |> Enum.map(fn chunk -> %{label: group_label(hd(chunk), column), rows: chunk} end)
    end
  end

  defp group_text(row, column_id) do
    case Map.get(row.cells, column_id) do
      %{text: text} -> text
      _cell -> nil
    end
  end

  defp group_label(row, column) do
    case group_text(row, column.id) do
      nil -> "#{column.short_label}: —"
      "" -> "#{column.short_label}: —"
      text -> "#{column.short_label}: #{text}"
    end
  end

  @doc "A DOM id fragment for a row key, safe for any key type."
  @spec key_id(term()) :: String.t()
  def key_id(key) when is_integer(key), do: Integer.to_string(key)

  def key_id(key) do
    key
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_-]/, fn char -> "_" <> Base.encode16(char) end)
  end

  @doc "The bar width the hook applies, as a percentage string, from a cell's position."
  @spec bar_width(map() | nil) :: String.t() | nil
  def bar_width(%{n: n}) when is_number(n), do: "#{round(n * 100)}"
  def bar_width(_cell), do: nil

  @doc "The points of a sparkline polyline for a series, in a 60 by 16 box."
  @spec sparkline([number()]) :: String.t() | nil
  def sparkline(series) when is_list(series) and length(series) > 1 do
    values = Enum.map(series, &(&1 * 1.0))
    {lo, hi} = Enum.min_max(values)
    span = if hi == lo, do: 1.0, else: hi - lo
    step = 60 / (length(values) - 1)

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {value, index} ->
      x = Float.round(index * step, 1)
      y = Float.round(15 - (value - lo) / span * 14, 1)
      "#{x},#{y}"
    end)
  end

  def sparkline(_series), do: nil
end
