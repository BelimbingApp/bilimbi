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
  `since`, `zoom`, `zoom_preset`, `reset`, `sort`, `expand`, `collapse`.
  The hook pushes `move` when a chip or a heading is dropped; the markup
  pushes the rest.

  ## Zoom

  The zoom is the height of a row in pixels, and it takes only the heights
  in `zoom_steps/0`: every one of them draws a visibly different table, so
  no step is a control that does nothing. The short ones are the compact
  rows (one line, small text) and the tall ones the normal rows; `mode/1`
  says which, and Compact and Normal are the two named heights a person
  jumps between.
  """

  # A row height is the rendered height of the row. A compact row holds one
  # line of small text, eighteen pixels at its shortest, which is Compact. A
  # normal row holds what a page draws at full size, an avatar or a second
  # line, thirty-two at its shortest, which is Normal, and forty is the
  # tallest offered. Nothing between twenty-six and thirty-two is offered:
  # the row would be drawn as one or the other and look the same as its
  # neighbour.
  @compact_steps [18, 22, 26]
  @normal_steps [32, 36, 40]
  @zoom_steps @compact_steps ++ @normal_steps
  @presets [compact: 18, normal: 32]

  @doc "The row heights a table takes, shortest first."
  @spec zoom_steps() :: [pos_integer()]
  def zoom_steps, do: @zoom_steps

  @doc "The row height a table opens at: normal rows."
  @spec default_zoom() :: pos_integer()
  def default_zoom, do: @presets[:normal]

  @doc "The two named row heights."
  @spec zoom_presets() :: [{:compact | :normal, pos_integer()}]
  def zoom_presets, do: @presets

  @doc """
  The offered row height nearest to an integer or the text of one; anything
  else is the default.
  """
  @spec normalize_zoom(term()) :: pos_integer()
  def normalize_zoom(value) when is_integer(value),
    do: Enum.min_by(@zoom_steps, &abs(&1 - value))

  def normalize_zoom(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_zoom(integer)
      _other -> default_zoom()
    end
  end

  def normalize_zoom(_value), do: default_zoom()

  @doc "One step taller or shorter, staying on the last step at either end."
  @spec step_zoom(pos_integer(), :in | :out) :: pos_integer()
  def step_zoom(zoom, direction) when direction in [:in, :out] do
    index = Enum.find_index(@zoom_steps, &(&1 == normalize_zoom(zoom)))
    next = if direction == :in, do: index + 1, else: index - 1
    Enum.at(@zoom_steps, next |> max(0) |> min(length(@zoom_steps) - 1))
  end

  @doc "Whether a row this tall is drawn compact or normal."
  @spec mode(pos_integer()) :: :compact | :normal
  def mode(zoom), do: if(normalize_zoom(zoom) in @compact_steps, do: :compact, else: :normal)

  @doc "The class that gives a cell its row height. Every step has one, written out."
  @spec row_class(pos_integer()) :: String.t()
  def row_class(zoom) do
    case normalize_zoom(zoom) do
      18 -> "h-4.5"
      22 -> "h-5.5"
      26 -> "h-6.5"
      32 -> "h-8"
      36 -> "h-9"
      40 -> "h-10"
    end
  end

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
