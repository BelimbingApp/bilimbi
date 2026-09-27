defmodule Bilimbi.Base.Grid.Zoom do
  @moduledoc """
  Semantic zoom: one number, the row height in pixels, decides how a grid
  draws.

  Zoomed out, rows are a few pixels tall and every cell is a coloured
  square, so thousands of rows by hundreds of columns fit one screen as a
  heat carpet. At a middle zoom a cell shows its number, an in-cell bar or
  a sparkline. Zoomed in, the grid is an ordinary table with full text,
  links and row actions. The bands are fixed here so every grid, and every
  test, agrees on where one mode ends and the next begins.
  """

  @min 2
  @max 40
  @carpet_max 6
  @mid_max 20
  @default 28
  @presets [carpet: 3, mid: 12, full: @default]

  @type mode :: :carpet | :mid | :full

  @doc "The row height a grid opens at: a full table."
  @spec default() :: pos_integer()
  def default, do: @default

  @doc "Row heights a control offers by name."
  @spec presets() :: [{mode(), pos_integer()}]
  def presets, do: @presets

  @doc "Clamps any integer, or the text of one, into the zoom range; anything else is the default."
  @spec normalize(term()) :: pos_integer()
  def normalize(value) when is_integer(value), do: value |> max(@min) |> min(@max)

  def normalize(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize(integer)
      _other -> @default
    end
  end

  def normalize(_value), do: @default

  @doc "The drawing mode a row height falls in."
  @spec mode(pos_integer()) :: mode()
  def mode(z) when z <= @carpet_max, do: :carpet
  def mode(z) when z <= @mid_max, do: :mid
  def mode(_z), do: :full

  @doc "One step in or out, staying in range."
  @spec step(pos_integer(), :in | :out) :: pos_integer()
  def step(z, :in), do: normalize(z + step_size(z))
  def step(z, :out), do: normalize(z - step_size(z))

  defp step_size(z) when z < 8, do: 1
  defp step_size(z) when z < 20, do: 2
  defp step_size(_z), do: 4

  @doc """
  The column width, in pixels, at a row height. A carpet cell is square; a
  compact cell is wide enough for a number; a full cell is a table cell
  whose width the browser decides.
  """
  @spec cell_width(pos_integer()) :: pos_integer()
  def cell_width(z) when z <= @carpet_max, do: z
  def cell_width(z) when z <= @mid_max, do: z * 6
  def cell_width(_z), do: 160

  @doc """
  The row height at which `rows` rows by `cols` columns fill a viewport of
  `width` by `height` pixels: how a dragged rectangle zooms in.
  """
  @spec fit(pos_integer(), pos_integer(), pos_integer(), pos_integer()) :: pos_integer()
  def fit(rows, cols, width, height) when rows > 0 and cols > 0 do
    by_height = div(height, rows)
    by_width = Enum.find(@max..@min//-1, @min, fn z -> cell_width(z) * cols <= width end)
    normalize(min(by_height, by_width))
  end

  def fit(_rows, _cols, _width, _height), do: @default
end
