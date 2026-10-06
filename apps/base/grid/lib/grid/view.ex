defmodule Bilimbi.Base.Grid.View do
  @moduledoc """
  What a person arranged on a list's columns, as one value that round-trips
  through the URL and through the account's saved setting: the table, the
  column specs in order, the lens of each column, the density of the rows,
  and the date a `delta` lens compares against.

  The page keeps its own sort, search, filters and pagination; this is only
  what the flexible table adds. Every field parses leniently from text and
  encodes to the short keys below, leaving defaults out so the address
  stays short:

      cols=name,company.name,employees:count
      lens=employees:count|bar
      density=compact  since=2026-01-01

  An address that carries any of those keys says what to show. One that
  carries none leaves it to what the account last arranged
  (`Bilimbi.Base.Grid.PageViews`), and to the page's own columns when the
  account arranged nothing.
  """

  @keys ~w(cols lens density since)

  defstruct table: nil,
            columns: [],
            lenses: %{},
            density: :normal,
            since: nil

  @type t :: %__MODULE__{
          table: String.t() | nil,
          columns: [String.t()],
          lenses: %{String.t() => String.t()},
          density: :normal | :compact,
          since: Date.t() | nil
        }

  @doc "Whether URL params say anything about the view, so they win over what was saved."
  @spec carried?(map()) :: boolean()
  def carried?(params) when is_map(params), do: Enum.any?(@keys, &Map.has_key?(params, &1))

  @doc "Reads a view from URL params. Unknown or malformed values fall back, never raise."
  @spec from_params(map(), String.t() | nil) :: t()
  def from_params(params, table) when is_map(params) do
    %__MODULE__{
      table: table,
      columns: split_list(Map.get(params, "cols")),
      lenses: parse_lenses(Map.get(params, "lens")),
      density: density(Map.get(params, "density")),
      since: params |> Map.get("since") |> parse_date()
    }
  end

  @doc "Writes the view as URL params, leaving defaults out so the address stays short."
  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = view) do
    %{}
    |> put_unless(:cols, Enum.join(view.columns, ","), "")
    |> put_unless(:lens, encode_lenses(view.lenses), "")
    |> put_unless(:density, Atom.to_string(view.density), "normal")
    |> put_unless(:since, view.since && Date.to_iso8601(view.since), nil)
  end

  @doc "Whether the view is the page's own: nothing arranged, so nothing to carry or keep."
  @spec default?(t()) :: boolean()
  def default?(%__MODULE__{} = view), do: to_params(view) == %{}

  @doc "The view as a plain JSON-storable map, the shape the account's setting keeps."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = view) do
    %{
      "columns" => view.columns,
      "lenses" => view.lenses,
      "density" => Atom.to_string(view.density),
      "since" => view.since && Date.to_iso8601(view.since)
    }
  end

  @doc "A view read back from a stored map. Anything malformed falls back, never raises."
  @spec from_map(map(), String.t() | nil) :: t()
  def from_map(map, table) when is_map(map) do
    %__MODULE__{
      table: table,
      columns: map |> Map.get("columns") |> split_list(),
      lenses: map |> Map.get("lenses") |> stored_lenses(),
      density: density(Map.get(map, "density")),
      since: map |> Map.get("since") |> parse_date()
    }
  end

  defp stored_lenses(lenses) when is_map(lenses) do
    lenses
    |> Enum.filter(fn {spec, lens} -> is_binary(spec) and is_binary(lens) end)
    |> Map.new()
  end

  defp stored_lenses(_other), do: %{}

  # Two densities and no more: anything that is not "compact" is the normal
  # table.
  defp density("compact"), do: :compact
  defp density(_other), do: :normal

  @doc "Sets the density of the rows; anything that is not `compact` is normal."
  @spec put_density(t(), term()) :: t()
  def put_density(%__MODULE__{} = view, value), do: %{view | density: density(value)}

  defp parse_date(%Date{} = date), do: date

  defp parse_date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      _other -> nil
    end
  end

  defp parse_date(_other), do: nil

  @doc "Adds a column spec at the end, once."
  @spec add_column(t(), String.t()) :: t()
  def add_column(%__MODULE__{} = view, spec) when is_binary(spec) do
    if spec in view.columns, do: view, else: %{view | columns: view.columns ++ [spec]}
  end

  @doc "Removes a column spec and its lens."
  @spec remove_column(t(), String.t()) :: t()
  def remove_column(%__MODULE__{} = view, spec) do
    %{view | columns: List.delete(view.columns, spec), lenses: Map.delete(view.lenses, spec)}
  end

  @doc "Moves `spec` before `before`, or to the end when `before` is nil."
  @spec move_column(t(), String.t(), String.t() | nil) :: t()
  def move_column(%__MODULE__{} = view, spec, before) do
    if spec in view.columns and spec != before do
      rest = List.delete(view.columns, spec)

      columns =
        case before && Enum.find_index(rest, &(&1 == before)) do
          nil -> rest ++ [spec]
          index -> List.insert_at(rest, index, spec)
        end

      %{view | columns: columns}
    else
      view
    end
  end

  @doc "The date a delta lens compares against: the view's, or thirty days ago."
  @spec since(t()) :: Date.t()
  def since(%__MODULE__{since: %Date{} = since}), do: since
  def since(%__MODULE__{}), do: Date.add(Date.utc_today(), -30)

  @doc "Sets the date a delta lens compares against; anything that is not a date clears it."
  @spec put_since(t(), term()) :: t()
  def put_since(%__MODULE__{} = view, value), do: %{view | since: parse_date(value)}

  @doc "Sets a column's lens; `value` drops the entry so the URL stays short."
  @spec put_lens(t(), String.t(), String.t()) :: t()
  def put_lens(%__MODULE__{} = view, spec, "value"),
    do: %{view | lenses: Map.delete(view.lenses, spec)}

  def put_lens(%__MODULE__{} = view, spec, lens) when is_binary(lens),
    do: %{view | lenses: Map.put(view.lenses, spec, lens)}

  defp split_list(nil), do: []
  defp split_list(""), do: []

  defp split_list(text) when is_binary(text) do
    text
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
    |> Enum.take(400)
  end

  defp split_list(list) when is_list(list), do: list |> Enum.filter(&is_binary/1) |> Enum.uniq()
  defp split_list(_other), do: []

  defp parse_lenses(nil), do: %{}

  defp parse_lenses(text) when is_binary(text) do
    text
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn pair ->
      case String.split(pair, "|", parts: 2) do
        [spec, lens] when spec != "" and lens != "" -> [{spec, lens}]
        _other -> []
      end
    end)
    |> Map.new()
  end

  defp parse_lenses(_other), do: %{}

  defp encode_lenses(lenses) when map_size(lenses) == 0, do: ""

  defp encode_lenses(lenses) do
    lenses |> Enum.sort() |> Enum.map_join(",", fn {spec, lens} -> "#{spec}|#{lens}" end)
  end

  defp put_unless(map, _key, value, value), do: map
  defp put_unless(map, key, value, _default), do: Map.put(map, key, value)
end
