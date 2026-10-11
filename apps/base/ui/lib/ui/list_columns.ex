defmodule Bilimbi.Base.UI.ListColumns do
  @moduledoc """
  Built-in columns for a record list rendered by `flex_table/1`.

  Catalog-backed lists use `Bilimbi.Base.Grid.Web.PageColumns`, which can add
  walked fields. A list without a Grid catalog uses this module for the same
  notch, built-in column arrangement, and row-height controls without adding a
  dependency on Base Grid. It takes the list's records as they are and never
  queries or changes them.

  A caller mounts the columns once, calls `load/3` whenever its visible rows
  change, and handles the component's `grid` event with `handle/2`. Built-in
  column ids are the ids used by the matching `<:col>` slots. Sorting is
  returned to the list because its query remains the source of row order.
  """

  alias Bilimbi.Base.UI.FlexTable

  @enforce_keys [:id, :builtins]
  defstruct id: nil,
            builtins: [],
            columns: [],
            column_views: [],
            rows: [],
            suggestions: [],
            add_query: "",
            zoom: FlexTable.default_zoom(),
            mode: :normal,
            expanded: %{}

  @type builtin :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          optional(:short_label) => String.t(),
          optional(:type) => atom(),
          optional(:sort) => String.t() | atom() | nil,
          optional(:sort_id) => String.t(),
          optional(:align) => :right
        }

  @type t :: %__MODULE__{}

  @doc "Mounts one built-in column set for a list."
  @spec mount(String.t(), [builtin()]) :: t()
  def mount(id, builtins) when is_binary(id) and is_list(builtins) do
    %__MODULE__{id: id, builtins: builtins}
  end

  @doc "Prepares the currently displayed records for `flex_table/1`."
  @spec load(t(), [term()], (term() -> term())) :: t()
  def load(%__MODULE__{} = state, records, key) when is_list(records) and is_function(key, 1) do
    visible = visible_ids(state)
    builtin_map = Map.new(state.builtins, &{&1.id, &1})

    %{
      state
      | column_views: Enum.map(visible, &(builtin_map |> Map.fetch!(&1) |> column_view())),
        rows: Enum.map(records, &%{key: key.(&1), cells: %{}, record: &1}),
        suggestions: [],
        add_query: "",
        mode: FlexTable.mode(state.zoom)
    }
  end

  @type outcome :: {:update, t()} | {:sort, String.t()} | :noop

  @doc "Applies a flexible-table operation to built-in columns or row height."
  @spec handle(t(), map()) :: outcome()
  def handle(%__MODULE__{} = state, %{"op" => "sort", "sort" => spec}) do
    case Enum.find(state.builtins, &(&1.id == spec)) do
      %{sort: sort} when not is_nil(sort) -> {:sort, to_string(sort)}
      _other -> :noop
    end
  end

  def handle(%__MODULE__{} = state, %{"op" => "suggest"} = params) do
    query = params |> Map.get("add", "") |> to_string() |> String.trim() |> String.slice(0, 120)
    {:update, %{state | add_query: query, suggestions: suggestions(state, query)}}
  end

  def handle(%__MODULE__{} = state, %{"op" => "add", "spec" => spec}) do
    if spec in builtin_ids(state) and spec not in visible_ids(state) do
      {:update, arrange(state, visible_ids(state) ++ [spec])}
    else
      :noop
    end
  end

  def handle(%__MODULE__{} = state, %{"op" => "add_typed"} = params) do
    query =
      params
      |> Map.get("add", state.add_query)
      |> to_string()
      |> String.trim()
      |> String.slice(0, 120)

    case Enum.find(suggestions(state, query), &exact?(&1, query)) ||
           List.first(suggestions(state, query)) do
      %{id: id} -> {:update, arrange(state, visible_ids(state) ++ [id])}
      nil -> :noop
    end
  end

  def handle(%__MODULE__{} = state, %{"op" => "remove", "spec" => spec}) do
    visible = visible_ids(state)

    if spec in visible and length(visible) > 1 do
      {:update, arrange(state, List.delete(visible, spec))}
    else
      :noop
    end
  end

  def handle(%__MODULE__{} = state, %{"op" => "move", "spec" => spec} = params) do
    before = Map.get(params, "before")
    {:update, arrange(state, move(visible_ids(state), spec, before))}
  end

  def handle(%__MODULE__{} = state, %{"op" => "zoom", "dir" => dir}) when dir in ["in", "out"] do
    direction = if dir == "in", do: :in, else: :out
    {:update, put_zoom(state, FlexTable.step_zoom(state.zoom, direction))}
  end

  def handle(%__MODULE__{} = state, %{"op" => "zoom_preset", "preset" => preset}) do
    case preset do
      "compact" -> {:update, put_zoom(state, 18)}
      "normal" -> {:update, put_zoom(state, 32)}
      _other -> :noop
    end
  end

  def handle(%__MODULE__{} = state, %{"op" => "reset"}) do
    {:update,
     state
     |> Map.put(:columns, [])
     |> refresh_column_views()
     |> put_zoom(FlexTable.default_zoom())
     |> Map.put(:suggestions, [])
     |> Map.put(:add_query, "")}
  end

  def handle(%__MODULE__{}, _params), do: :noop

  defp arrange(state, columns) do
    state
    |> Map.put(:columns, columns)
    |> refresh_column_views()
    |> Map.put(:suggestions, [])
    |> Map.put(:add_query, "")
  end

  defp refresh_column_views(state) do
    builtin_map = Map.new(state.builtins, &{&1.id, &1})

    %{
      state
      | column_views:
          Enum.map(visible_ids(state), &(builtin_map |> Map.fetch!(&1) |> column_view()))
    }
  end

  defp put_zoom(state, zoom), do: %{state | zoom: zoom, mode: FlexTable.mode(zoom)}

  defp visible_ids(%__MODULE__{columns: []} = state), do: builtin_ids(state)
  defp visible_ids(%__MODULE__{columns: columns}), do: columns

  defp builtin_ids(state), do: Enum.map(state.builtins, & &1.id)

  defp column_view(builtin) do
    %{
      id: builtin.id,
      spec: builtin.id,
      label: builtin.label,
      short_label: Map.get(builtin, :short_label, builtin.label),
      type: Map.get(builtin, :type, :string),
      kind: :slot,
      lens: :value,
      lenses: [:value],
      sort: Map.get(builtin, :sort),
      sortable: not is_nil(Map.get(builtin, :sort)),
      sort_id: Map.get(builtin, :sort_id),
      removable: true,
      align: Map.get(builtin, :align)
    }
  end

  defp suggestions(_state, ""), do: []

  defp suggestions(state, query) do
    wanted = String.downcase(query)
    shown = visible_ids(state)

    state.builtins
    |> Enum.reject(&(&1.id in shown))
    |> Enum.filter(fn builtin ->
      String.contains?(String.downcase(builtin.label), wanted) or
        String.contains?(String.downcase(builtin.id), wanted)
    end)
    |> Enum.map(&column_view/1)
  end

  defp exact?(column, query) do
    wanted = String.downcase(query)
    String.downcase(column.label) == wanted or String.downcase(column.id) == wanted
  end

  defp move(columns, spec, before) do
    if spec in columns and spec != before do
      rest = List.delete(columns, spec)

      case before && Enum.find_index(rest, &(&1 == before)) do
        nil -> rest ++ [spec]
        index -> List.insert_at(rest, index, spec)
      end
    else
      columns
    end
  end
end
