defmodule Bilimbi.Base.UI.FlexTable do
  @moduledoc """
  The plain data `Bilimbi.Base.UI.Components.flex_table/1` takes, and the
  small pure helpers it renders with.

  The component is presentation only: it knows nothing about catalogs,
  links or queries. A host (a list page that lets people add walked
  columns) hands it columns and prepared cells in these shapes and handles
  the one event it pushes.

  ## Columns

      %{
        id: "company-name",         # DOM-safe, unique in the table
        spec: "company.name",       # what the host's event handlers get back
        label: "Company › Name",    # full path label, the tooltip
        short_label: "Name",        # what the header shows
        type: :string,              # :integer | :float | :decimal | :string | :boolean | :date | :datetime | :enum
        kind: :field,               # :field | :rollup | :slot
        lens: :value,               # :value | :bar | :band | :trend | :delta
        lenses: [:value, :band],    # the lenses this column allows
        sortable: true,
        removable: true,
        align: nil                  # or :right
      }

  A `:slot` column is drawn by the caller's `<:col>` of the same `id` and
  needs no cell; the other kinds are drawn from their cells.

  ## Cells

  `rows` is a list of `%{key: term, cells: %{column_id => cell}}`, where a
  cell is `%{text, value, n, band, scale, series}`: the text to show, the
  raw value, its 0..1 position within the column's range or nil, the band
  that position falls in, whether the scale is `:sequential`,
  `:categorical` or `:binary`, and the twelve monthly values a trend lens
  draws.

  ## Events

  Everything the component does is one event, `event` (default `"grid"`),
  with an `op`: `add`, `add_typed`, `suggest`, `remove`, `move`, `lens`,
  `since`, `density`, `sort`, `expand`, `collapse`. The hook pushes `move`
  when a chip or a heading is dropped; the markup pushes the rest.
  """

  @doc "The word a lens is called."
  @spec lens_label(atom()) :: String.t()
  def lens_label(:value), do: "Value"
  def lens_label(:bar), do: "Bar"
  def lens_label(:band), do: "Colour band"
  def lens_label(:trend), do: "Trend"
  def lens_label(:delta), do: "Change since a date"

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
