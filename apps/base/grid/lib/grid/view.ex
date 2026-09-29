defmodule Bilimbi.Base.Grid.View do
  @moduledoc """
  What a grid currently shows, as one value that round-trips through the
  URL and a saved view: the table, the column specs in order, the lens of
  each column, the zoom, the sort, the search, the page, the group and
  pivot, what it follows, and the date a `delta` lens compares against.

  The URL is the state, so a reload or a shared link reopens the same grid
  (`DESIGN.md` "Pagination controls"). Every field parses leniently from
  text and encodes to the short keys below:

      cols=name,company.name,employees:count
      lens=employees:count|bar
      z=12  sort=employees:count  dir=desc  q=acme  page=2  per_page=50  group=status
      pivot=company.name  since=2026-01-01  follow=company  focus=73

  `follow` names how the grid follows a workspace selection: `self` for the
  root table's own record, or a one-link whose target records the selected
  kind; `focus` is the key of the record last selected, which narrows the
  rows to the ones reaching it.
  """

  alias Bilimbi.Base.Grid.Zoom

  @page_sizes [25, 50, 100, 300]

  defstruct table: nil,
            columns: [],
            lenses: %{},
            zoom: 28,
            sort: nil,
            dir: :asc,
            search: "",
            page: 1,
            page_size: 25,
            group: nil,
            pivot: nil,
            follow: nil,
            focus: nil,
            since: nil,
            slug: nil

  @type t :: %__MODULE__{
          table: String.t() | nil,
          columns: [String.t()],
          lenses: %{String.t() => String.t()},
          zoom: pos_integer(),
          sort: String.t() | nil,
          dir: :asc | :desc,
          search: String.t(),
          page: pos_integer(),
          page_size: pos_integer(),
          group: String.t() | nil,
          pivot: String.t() | nil,
          follow: String.t() | nil,
          focus: String.t() | nil,
          since: Date.t() | nil,
          slug: String.t() | nil
        }

  @doc "The page sizes the full-table mode offers."
  @spec page_sizes() :: [pos_integer()]
  def page_sizes, do: @page_sizes

  @doc "Reads a view from URL params. Unknown or malformed values fall back, never raise."
  @spec from_params(map(), String.t() | nil) :: t()
  def from_params(params, table) when is_map(params) do
    %__MODULE__{
      table: table,
      columns: split_list(Map.get(params, "cols")),
      lenses: parse_lenses(Map.get(params, "lens")),
      zoom: Zoom.normalize(Map.get(params, "z")),
      sort: blank_to_nil(Map.get(params, "sort")),
      dir: if(Map.get(params, "dir") == "desc", do: :desc, else: :asc),
      search: params |> Map.get("q", "") |> to_string() |> String.slice(0, 255),
      page: positive(Map.get(params, "page"), 1),
      page_size: page_size(Map.get(params, "per_page")),
      group: blank_to_nil(Map.get(params, "group")),
      pivot: params |> Map.get("pivot") |> blank_to_nil() |> pivot_of(Map.get(params, "group")),
      follow: params |> Map.get("follow") |> blank_to_nil() |> follow_name(),
      focus: params |> Map.get("focus") |> blank_to_nil() |> focus_key(),
      since: params |> Map.get("since") |> parse_date(),
      slug: blank_to_nil(Map.get(params, "v"))
    }
  end

  # A pivot needs grouped rows, and a column other than the grouped one.
  defp pivot_of(nil, _group), do: nil

  defp pivot_of(pivot, group),
    do: if(blank_to_nil(group) in [nil, pivot], do: nil, else: pivot)

  defp parse_date(%Date{} = date), do: date

  defp parse_date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      _other -> nil
    end
  end

  defp parse_date(_other), do: nil

  defp follow_name(nil), do: nil
  defp follow_name(name), do: if(Regex.match?(~r/^[a-z][a-z0-9_]*$/, name), do: name)

  defp focus_key(nil), do: nil
  defp focus_key(key), do: if(byte_size(key) <= 64 and not (key =~ ~r{[/?#\s]}), do: key)

  @doc "Writes the view as URL params, leaving defaults out so the address stays short."
  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = view) do
    %{}
    |> put_unless(:cols, Enum.join(view.columns, ","), "")
    |> put_unless(:lens, encode_lenses(view.lenses), "")
    |> put_unless(:z, view.zoom, Zoom.default())
    |> put_unless(:sort, view.sort, nil)
    |> put_unless(:dir, if(view.dir == :desc, do: "desc"), nil)
    |> put_unless(:q, view.search, "")
    |> put_unless(:page, view.page, 1)
    |> put_unless(:per_page, view.page_size, 25)
    |> put_unless(:group, view.group, nil)
    |> put_unless(:pivot, view.pivot, nil)
    |> put_unless(:follow, view.follow, nil)
    |> put_unless(:focus, view.focus, nil)
    |> put_unless(:since, view.since && Date.to_iso8601(view.since), nil)
    |> put_unless(:v, view.slug, nil)
  end

  @doc "The view as a plain JSON-storable map, the shape a saved view keeps."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = view) do
    %{
      "table" => view.table,
      "columns" => view.columns,
      "lenses" => view.lenses,
      "zoom" => view.zoom,
      "sort" => view.sort,
      "dir" => Atom.to_string(view.dir),
      "search" => view.search,
      "page_size" => view.page_size,
      "group" => view.group,
      "pivot" => view.pivot,
      "follow" => view.follow,
      "since" => view.since && Date.to_iso8601(view.since)
    }
  end

  @doc "A view read back from a saved map; page starts at 1."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      table: Map.get(map, "table"),
      columns: map |> Map.get("columns", []) |> Enum.filter(&is_binary/1),
      lenses:
        map
        |> Map.get("lenses", %{})
        |> Enum.filter(fn {k, v} -> is_binary(k) and is_binary(v) end)
        |> Map.new(),
      zoom: Zoom.normalize(Map.get(map, "zoom")),
      sort: blank_to_nil(Map.get(map, "sort")),
      dir: if(Map.get(map, "dir") == "desc", do: :desc, else: :asc),
      search: map |> Map.get("search", "") |> to_string(),
      page: 1,
      page_size: page_size(Map.get(map, "page_size")),
      group: blank_to_nil(Map.get(map, "group")),
      pivot: map |> Map.get("pivot") |> blank_to_nil() |> pivot_of(Map.get(map, "group")),
      follow: map |> Map.get("follow") |> blank_to_nil() |> follow_name(),
      since: map |> Map.get("since") |> parse_date()
    }
  end

  @doc "Adds a column spec at the end, once."
  @spec add_column(t(), String.t()) :: t()
  def add_column(%__MODULE__{} = view, spec) when is_binary(spec) do
    if spec in view.columns, do: view, else: %{view | columns: view.columns ++ [spec]}
  end

  @doc "Removes a column spec, its lens, and the sort or group on it."
  @spec remove_column(t(), String.t()) :: t()
  def remove_column(%__MODULE__{} = view, spec) do
    %{
      view
      | columns: List.delete(view.columns, spec),
        lenses: Map.delete(view.lenses, spec),
        sort: if(view.sort == spec, do: nil, else: view.sort),
        group: if(view.group == spec, do: nil, else: view.group),
        pivot: if(view.pivot == spec, do: nil, else: view.pivot)
    }
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

  @doc "Sets a column's lens; `value` drops the entry so the URL stays short."
  @spec put_lens(t(), String.t(), String.t()) :: t()
  def put_lens(%__MODULE__{} = view, spec, "value"),
    do: %{view | lenses: Map.delete(view.lenses, spec)}

  def put_lens(%__MODULE__{} = view, spec, lens) when is_binary(lens),
    do: %{view | lenses: Map.put(view.lenses, spec, lens)}

  @doc "Sorts by `spec`, flipping the direction when it is already the sort."
  @spec sort_by(t(), String.t()) :: t()
  def sort_by(%__MODULE__{sort: spec, dir: :asc} = view, spec), do: %{view | dir: :desc, page: 1}

  def sort_by(%__MODULE__{sort: spec, dir: :desc} = view, spec),
    do: %{view | sort: nil, dir: :asc, page: 1}

  def sort_by(%__MODULE__{} = view, spec), do: %{view | sort: spec, dir: :asc, page: 1}

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

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp positive(value, default) do
    case value do
      integer when is_integer(integer) and integer > 0 ->
        integer

      text when is_binary(text) ->
        case Integer.parse(text) do
          {integer, ""} when integer > 0 -> integer
          _other -> default
        end

      _other ->
        default
    end
  end

  defp page_size(value) do
    size = positive(value, 25)
    if size in @page_sizes, do: size, else: 25
  end

  defp put_unless(map, _key, value, value), do: map
  defp put_unless(map, key, value, _default), do: Map.put(map, key, value)
end
