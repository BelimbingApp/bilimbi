defmodule Bilimbi.Base.Grid.Lens do
  @moduledoc """
  A lens is how one column's values are shown: the raw value, a bar scaled
  to the column's range, or a colour band. The same column can be switched
  between the lenses its type allows; the data does not change, the reading
  does. `:trend` is in the vocabulary for the sparkline a rollup over a
  dated table will offer; no column offers it yet.

  `cell/4` prepares one value for every mode at once: its text, its
  position on the column's range as a number from 0 to 1, and the band
  (0 to 4) that position falls in, so the table, the compact view and the
  heat carpet all draw from one prepared cell.
  """

  alias Bilimbi.Base.Grid.Column

  @lenses [:value, :bar, :band, :trend]
  @bands 5

  @type lens :: :value | :bar | :band | :trend

  @type cell :: %{
          text: String.t(),
          value: term(),
          n: float() | nil,
          band: non_neg_integer() | nil,
          scale: :sequential | :categorical | :binary | nil
        }

  @doc "Every lens name."
  @spec all() :: [lens()]
  def all, do: @lenses

  @doc "The lenses a column's values allow."
  @spec available(Column.t()) :: [lens()]
  def available(%Column{} = column) do
    if Column.numeric?(column), do: [:value, :bar, :band], else: [:value, :band]
  end

  @doc "The lens a column shows by default."
  @spec default(Column.t()) :: lens()
  def default(%Column{}), do: :value

  @doc "Parses a lens name, falling back to `:value`."
  @spec normalize(term(), Column.t()) :: lens()
  def normalize(name, %Column{} = column) when is_binary(name) do
    case Enum.find(@lenses, &(Atom.to_string(&1) == name)) do
      nil -> :value
      lens -> if lens in available(column), do: lens, else: :value
    end
  end

  def normalize(lens, %Column{} = column) when is_atom(lens) do
    if lens in available(column), do: lens, else: :value
  end

  @doc "The lens's word."
  @spec label(lens()) :: String.t()
  def label(:value), do: "Value"
  def label(:bar), do: "Bar"
  def label(:band), do: "Colour band"
  def label(:trend), do: "Trend"

  @doc """
  Prepares one value: its text, its 0..1 position within `stats` (the
  column's `%{min, max}` over the whole set), and the band that position
  falls in. Text and enum values get a categorical band from a stable hash,
  booleans a binary one, so a colour carpet reads them too.
  """
  @spec cell(term(), Column.t(), %{min: term(), max: term()} | nil, lens()) :: cell()
  def cell(value, %Column{} = column, stats, _lens) do
    {n, scale} = position(value, column, stats)

    %{
      text: text(value, column),
      value: value,
      n: n,
      band: band(n, scale, value),
      scale: scale
    }
  end

  defp position(nil, _column, _stats), do: {nil, nil}

  defp position(value, %Column{} = column, stats) do
    cond do
      Column.numeric?(column) and is_map(stats) ->
        {normalize_number(value, stats), :sequential}

      column.type == :boolean ->
        {if(value, do: 1.0, else: 0.0), :binary}

      true ->
        {categorical(value), :categorical}
    end
  end

  defp normalize_number(value, %{min: min, max: max}) when not is_nil(min) and not is_nil(max) do
    v = to_number(value)
    lo = to_number(min)
    hi = to_number(max)

    cond do
      is_nil(v) or is_nil(lo) or is_nil(hi) -> nil
      hi == lo -> 0.5
      true -> ((v - lo) / (hi - lo)) |> max(0.0) |> min(1.0)
    end
  end

  defp normalize_number(_value, _stats), do: nil

  defp to_number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_number(number) when is_number(number), do: number * 1.0
  defp to_number(%Date{} = date), do: date |> Date.to_gregorian_days() |> Kernel.*(1.0)

  defp to_number(%NaiveDateTime{} = naive),
    do: naive |> NaiveDateTime.diff(~N[1970-01-01 00:00:00]) |> Kernel.*(1.0)

  defp to_number(%DateTime{} = datetime), do: datetime |> DateTime.to_unix() |> Kernel.*(1.0)
  defp to_number(_other), do: nil

  # A text value's colour is its own: the same word is the same colour on
  # every row and every grid, without a lookup table.
  defp categorical(value) do
    hash = :erlang.phash2(to_string(value), 8)
    hash / 7
  end

  defp band(nil, _scale, _value), do: nil
  defp band(_n, :binary, value), do: if(value, do: @bands - 1, else: 0)
  defp band(n, :categorical, _value), do: round(n * 7)
  defp band(n, :sequential, _value), do: min(trunc(n * @bands), @bands - 1)

  @doc "The text of a value, as the compact and carpet views show it."
  @spec text(term(), Column.t()) :: String.t()
  def text(nil, _column), do: ""
  def text(true, _column), do: "Yes"
  def text(false, _column), do: "No"

  def text(%Decimal{} = decimal, _column),
    do: decimal |> Decimal.round(2) |> Decimal.to_string(:normal)

  def text(float, _column) when is_float(float), do: :erlang.float_to_binary(float, decimals: 2)
  def text(integer, _column) when is_integer(integer), do: Integer.to_string(integer)
  def text(%Date{} = date, _column), do: Date.to_iso8601(date)

  def text(%NaiveDateTime{} = naive, _column),
    do:
      naive
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()
      |> String.replace("T", " ")

  def text(%DateTime{} = datetime, _column),
    do:
      datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601() |> String.replace("T", " ")

  def text(other, _column), do: to_string(other)
end
