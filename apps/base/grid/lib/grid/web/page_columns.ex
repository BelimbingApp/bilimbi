defmodule Bilimbi.Base.Grid.Web.PageColumns do
  @moduledoc """
  Walked columns for a list page that already has rows of its own.

  A list page keeps its query, filters, sort and pagination, and declares
  the columns it draws itself as built-ins. This struct adds everything the
  grid brings on top: columns a person walks to through the catalog (added,
  removed, reordered and read through lenses), compact or normal rows, and
  rollups that expand in place. The page's rows stay the rows; the walked
  columns are fetched for exactly those rows with `Grid.attach/5`.

  The page holds one `%PageColumns{}` in its assigns and:

    1. builds it at mount with `mount/3`, from the session's
       `current_scope`;
    2. reads `cols`, `lens`, `density` and `since` from the URL with
       `from_params/2` and merges `params/1` back into every path it
       patches to;
    3. after loading its page, calls `load/3` with the entries and a key
       function;
    4. renders `flex_table/1` from `column_views`, `rows`, `mode`, `cost`
       and `since`, with a `<:col>` slot per built-in id;
    5. delegates its `"grid"` event to `handle/2`.

  What a person arranges is remembered for their account and this page
  (`Bilimbi.Base.Grid.PageViews`): `handle/2` keeps it on every change, and
  an address that says nothing about columns, lenses or density opens the page
  the way the account left it. An address that carries any of them wins,
  so a shared link shows what its sender saw and changes nobody's memory
  until the reader arranges something.

  A page whose table is not in the account's catalog still works: the
  built-ins render and the add-a-column box offers nothing.
  """

  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.PageViews
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Grid.Web.Host
  alias Bilimbi.Base.Settings

  @enforce_keys [:catalog, :table, :builtins, :view, :account]
  defstruct catalog: nil,
            table: nil,
            builtins: [],
            view: %View{},
            account: nil,
            remembered: nil,
            cost: nil,
            since: nil,
            extras: [],
            dropped: [],
            column_views: [],
            rows: [],
            mode: :normal,
            suggestions: [],
            add_query: "",
            expanded: %{}

  @type builtin :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:type) => Column.t() | atom(),
          optional(:sort) => String.t(),
          optional(:sort_id) => String.t(),
          optional(:align) => :right | nil
        }

  @type t :: %__MODULE__{}

  @doc """
  Builds the state for a page whose rows are `table_id` rows, with its
  built-in columns, for the signed-in `current_scope`. Reads what the
  account last arranged on this page.
  """
  @spec mount(map(), String.t(), [builtin()]) :: t()
  def mount(%{scope: scope} = current_scope, table_id, builtins)
      when is_binary(table_id) and is_list(builtins) do
    catalog = Grid.catalog(scope)

    table =
      case Grid.fetch_table(catalog, table_id) do
        {:ok, table} -> table
        :error -> nil
      end

    # The arrangement is the signed-in account's own, as its dashboard is.
    account =
      Settings.Scope.user(
        Bilimbi.Base.UI.current_user_id(current_scope),
        current_scope.user["company_id"],
        scope.tenant.id
      )

    remembered =
      case PageViews.fetch(account, table_id) do
        {:ok, view} -> view
        :error -> nil
      end

    %__MODULE__{
      catalog: catalog,
      table: table,
      builtins: builtins,
      view: %View{table: table_id},
      account: account,
      remembered: remembered
    }
  end

  @doc """
  Reads the walked columns, lenses, density and comparison date. The URL says
  them when it carries any of them; otherwise the account's remembered
  arrangement does, and the page's own columns when there is none.
  """
  @spec from_params(t(), map()) :: t()
  def from_params(%__MODULE__{} = state, params) do
    view =
      cond do
        View.carried?(params) -> View.from_params(params, state.view.table)
        state.remembered -> state.remembered
        true -> %View{table: state.view.table}
      end

    %{state | view: view, suggestions: [], add_query: "", expanded: %{}}
  end

  @doc "The URL params a page merges into its own: only what differs from the defaults."
  @spec params(t()) :: map()
  def params(%__MODULE__{view: view}), do: View.to_params(view)

  @doc """
  Prepares the component's columns and rows for this page of entries.
  `key` gives a row's key. A built-in column is drawn by the page's own
  `<:col>`, so a row carries cells only for the walked columns.
  """
  @spec load(t(), [term()], (term() -> term())) :: t()
  def load(%__MODULE__{} = state, entries, key) when is_list(entries) and is_function(key, 1) do
    builtin_ids = Enum.map(state.builtins, & &1.id)

    {kept, dropped} =
      case state.table do
        nil ->
          {Enum.filter(state.view.columns, &(&1 in builtin_ids)),
           state.view.columns -- builtin_ids}

        table ->
          Host.split_columns(state.catalog, table, state.view, builtin_ids)
      end

    kept = if kept == [], do: builtin_ids, else: kept
    extras = Enum.filter(kept, &is_struct(&1, Column))
    kept_specs = Enum.map(kept, &if(is_binary(&1), do: &1, else: &1.spec))
    # The page's own order with nothing walked is the default, and the URL
    # says nothing about a default. A lens belongs to a walked column that is
    # shown; one named for anything else is dropped rather than carried.
    view = %{
      state.view
      | columns: if(kept_specs == builtin_ids, do: [], else: kept_specs),
        lenses: Map.take(state.view.lenses, Enum.map(extras, & &1.spec))
    }

    keys = Enum.map(entries, key)

    values =
      if extras == [] or state.table == nil,
        do: %{},
        else:
          Grid.attach(state.catalog, state.table, keys, extras, Host.lens_options(extras, view))

    # Only a bar or a band is scaled to the column's range over the whole
    # table, so only then is that range read, and its cost with it.
    scaled = Enum.filter(extras, &(Host.lens(view, &1) in [:bar, :band]))

    {stats, cost} =
      if scaled == [] or state.table == nil,
        do: {%{}, nil},
        else: Grid.stats(state.catalog, state.table, scaled)

    extra_cells = Host.attached_cells(values, extras, stats, view)
    builtin_map = Map.new(state.builtins, &{&1.id, &1})

    column_views =
      Enum.map(kept, fn
        id when is_binary(id) ->
          builtin_view(Map.fetch!(builtin_map, id))

        %Column{} = column ->
          column |> List.wrap() |> Host.column_views(view) |> hd()
      end)

    rows = Enum.map(keys, &%{key: &1, cells: Map.get(extra_cells, &1, %{})})

    %{
      state
      | view: view,
        extras: extras,
        dropped: dropped,
        column_views: column_views,
        rows: rows,
        mode: view.density,
        cost: Host.cost(cost),
        since: View.since(view)
    }
  end

  defp builtin_view(builtin) do
    %{
      id: builtin.id,
      spec: builtin.id,
      label: builtin.label,
      short_label: builtin.label,
      type: builtin.type,
      kind: :slot,
      lens: :value,
      lenses: [:value],
      sortable: Map.has_key?(builtin, :sort),
      sort_id: Map.get(builtin, :sort_id),
      removable: true,
      align: Map.get(builtin, :align)
    }
  end

  @type outcome ::
          {:patch, t()}
          | {:update, t()}
          | {:sort, String.t()}
          | :noop

  @doc """
  Applies one `flex_table` op. A `{:patch, state}` outcome has already been
  remembered for the account; the page patches its URL with `params/1`.
  `{:update, state}` changes only what is on screen, and `{:sort, key}` is
  a built-in column's sort, which the page already knows how to do.
  """
  @spec handle(t(), map()) :: outcome()
  def handle(%__MODULE__{} = state, params) when is_map(params) do
    builtin_ids = Enum.map(state.builtins, & &1.id)
    builtin_sorts = state.builtins |> Enum.filter(&Map.has_key?(&1, :sort)) |> Enum.map(& &1.id)
    # An empty column list means the page default; an op that changes columns
    # starts from that default spelled out, so a built-in is never lost.
    spelled =
      if state.view.columns == [],
        do: %{state | view: %{state.view | columns: builtin_ids}},
        else: state

    case params do
      %{"op" => "sort", "sort" => spec} ->
        if spec in builtin_sorts, do: {:sort, spec}, else: :noop

      _other ->
        case Host.apply(params, spelled.view, spelled.extras) do
          {:patch, view} ->
            arrange(spelled, view, builtin_ids)

          {:suggest, text} ->
            {:update, suggest(state, text)}

          {:add_typed, text} ->
            add_typed(spelled, text, builtin_ids)

          {:expand, spec, key} ->
            {:update, expand(state, spec, key)}

          {:collapse, spec, key} ->
            {:update, collapse(state, spec, key)}

          :noop ->
            :noop
        end
    end
  end

  # The page's own order with nothing walked is the default, which neither
  # the URL nor the account's memory spells out.
  defp arrange(state, %View{} = view, builtin_ids) do
    view = if view.columns == builtin_ids, do: %{view | columns: []}, else: view
    state = %{state | view: view, suggestions: [], add_query: ""}
    {:patch, remember(state)}
  end

  defp remember(%__MODULE__{account: account, view: view} = state) do
    case PageViews.remember(account, view) do
      :ok -> %{state | remembered: if(View.default?(view), do: nil, else: view)}
      {:error, _changeset} -> state
    end
  end

  defp suggest(%{table: nil} = state, text), do: %{state | add_query: text, suggestions: []}

  defp suggest(state, text) do
    suggestions =
      if text == "",
        do: [],
        else: Grid.suggest(state.catalog, state.table, text, exclude: state.view.columns)

    %{state | add_query: text, suggestions: Host.column_views(suggestions, state.view)}
  end

  defp add_typed(%{table: nil}, _text, _builtin_ids), do: :noop

  defp add_typed(state, text, builtin_ids) do
    resolved =
      case Grid.resolve(state.catalog, state.table, [text]) do
        {:ok, [column]} ->
          column.spec

        {:error, _reason} ->
          state.catalog
          |> Grid.suggest(state.table, text, exclude: state.view.columns, limit: 1)
          |> Enum.map(& &1.spec)
          |> List.first()
      end

    case resolved do
      nil ->
        :noop

      spec ->
        arrange(state, View.add_column(state.view, spec), builtin_ids)
    end
  end

  defp expand(state, spec, key) do
    with %Column{} = column <- Enum.find(state.extras, &(&1.spec == spec)),
         %{key: row_key} <- Enum.find(state.rows, &(to_string(&1.key) == key)) do
      rows = Host.expansion(state.catalog, state.table, row_key, column)

      %{
        state
        | expanded:
            Map.update(
              state.expanded,
              row_key,
              %{column.id => rows},
              &Map.put(&1, column.id, rows)
            )
      }
    else
      _other -> state
    end
  end

  defp collapse(state, spec, key) do
    with %Column{} = column <- Enum.find(state.extras, &(&1.spec == spec)),
         %{key: row_key} <- Enum.find(state.rows, &(to_string(&1.key) == key)) do
      %{state | expanded: Map.update(state.expanded, row_key, %{}, &Map.delete(&1, column.id))}
    else
      _other -> state
    end
  end
end
