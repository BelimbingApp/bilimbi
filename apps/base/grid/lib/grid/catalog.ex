defmodule Bilimbi.Base.Grid.Catalog do
  @moduledoc """
  The tables one account may read, and the paths between them.

  `for_scope/1` reads the installed contribution snapshot once, keeps only
  the tables whose capability the scope's actor holds and, within them,
  only the fields no operator restricted for a role they hold, and settles which
  key of its source each of their fields is read from, so a catalog is
  both the vocabulary of a grid and the proof of what it may show. Every
  later call takes the catalog, not the scope: a path is resolved against
  it, a query is built from it, and a table it left out cannot be reached
  by any spelling of a path. Refresh it where the page refreshes its own
  capabilities, at mount.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.Field
  alias Bilimbi.Base.Grid.Link
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Scope

  @enforce_keys [:scope, :tables]
  defstruct scope: nil, tables: %{}

  @type t :: %__MODULE__{scope: Scope.t(), tables: %{String.t() => Table.t()}}

  @max_suggestions 12

  @doc "Every declared table, whatever the reader may see."
  @spec installed() :: %{tables: %{String.t() => Table.t()}}
  def installed, do: ContributionRegistry.consumer!(:grid)

  @doc "The catalog this scope's actor may read. A system actor reads nothing here."
  @spec for_scope(Scope.t()) :: t()
  def for_scope(%Scope{} = scope) do
    allowed = allowed_capabilities(scope)
    %{tables: tables} = installed()

    restricted = Authz.restricted_fields(scope)

    visible =
      tables
      |> Enum.filter(fn {_id, table} -> table.capability in allowed end)
      |> Map.new(fn {id, table} ->
        {id,
         table
         |> without_restricted(restricted |> Map.get(id, %{}) |> Map.keys())
         |> resolve_columns!(scope)}
      end)

    %__MODULE__{scope: scope, tables: visible}
  end

  # A field an operator restricted for a role this reader holds is not
  # in their catalog (`Bilimbi.Base.Authz.restricted_fields/1`). Left out, not
  # marked: a path to it is then unknown, the add box never offers it, and a
  # kept view that names it loses that column, exactly as a table the reader
  # may not see.
  defp without_restricted(%Table{} = table, []), do: table

  defp without_restricted(%Table{} = table, restricted) do
    %{
      table
      | fields: Map.drop(table.fields, restricted),
        field_order: table.field_order -- restricted
    }
  end

  # A field that declares no column is read from the source key its id
  # names. The id is compared with each key as a string, so contribution
  # data never creates an atom. A field no key answers to is refused here,
  # naming the field, before any statement is built from it.
  defp resolve_columns!(%Table{} = table, scope) do
    keys = source_keys(table.source, scope)

    fields =
      Map.new(table.fields, fn
        {id, %Field{column: nil} = field} ->
          case Enum.find(keys, &(Atom.to_string(&1) == id)) do
            nil ->
              raise ArgumentError,
                    "invalid grid table from #{table.owner} (#{inspect(table.id)}): field " <>
                      "#{id} names no key its source #{inspect(table.source)} selects; " <>
                      "it selects #{inspect(keys)}"

            column ->
              {id, %{field | column: column}}
          end

        entry ->
          entry
      end)

    %{table | fields: fields}
  end

  # The keys a source's query selects, read from the query it builds for a
  # real scope and kept for as long as that compiled source is loaded. The
  # catalog asks only once a scope exists, never at boot: a source may ask
  # another module's public API for what bounds its rows, and that reads
  # the database. The keys never depend on the scope (`Source`), which is
  # what makes them safe to keep.
  defp source_keys(source, scope) do
    cache = {__MODULE__, :source_keys, source, source.module_info(:md5)}

    case :persistent_term.get(cache, nil) do
      nil ->
        keys = selected_keys(Ecto.Queryable.to_query(source.query(scope)))
        :persistent_term.put(cache, keys)
        keys

      keys ->
        keys
    end
  end

  defp selected_keys(%Ecto.Query{select: select, from: from}) do
    case select do
      %{expr: {:%{}, _meta, pairs}} -> Keyword.keys(pairs)
      %{expr: {:&, _meta, [0]}, take: %{0 => {_kind, fields}}} -> fields
      _struct -> schema_fields(from.source)
    end
  end

  defp schema_fields({_table, schema}) when is_atom(schema) and not is_nil(schema),
    do: schema.__schema__(:fields)

  defp schema_fields(_source), do: []

  # A system actor holds no grants a table capability could match, so it
  # reads nothing here; `Authz.scope_actor/1` says so for it.
  defp allowed_capabilities(scope) do
    case Authz.scope_actor(scope) do
      {:ok, actor} ->
        actor |> Authz.effective_capabilities() |> Map.fetch!(:allowed) |> MapSet.new()

      {:error, :no_authenticated_actor} ->
        MapSet.new()
    end
  end

  @spec fetch_table(t(), String.t()) :: {:ok, Table.t()} | :error
  def fetch_table(%__MODULE__{tables: tables}, id) when is_binary(id), do: Map.fetch(tables, id)
  def fetch_table(%__MODULE__{}, _id), do: :error

  @doc "Resolves one column spec against a root table of this catalog."
  @spec resolve(t(), Table.t(), String.t()) :: {:ok, Column.t()} | {:error, term()}
  def resolve(%__MODULE__{} = catalog, %Table{} = root, spec) do
    Column.resolve(spec, root, &fetch_table(catalog, &1))
  end

  @doc """
  Resolves every spec, or reports the first one that fails. Duplicate specs
  collapse to one column, in first-seen order.
  """
  @spec resolve_all(t(), Table.t(), [String.t()]) ::
          {:ok, [Column.t()]} | {:error, {String.t(), term()}}
  def resolve_all(%__MODULE__{} = catalog, %Table{} = root, specs) when is_list(specs) do
    specs
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
      case resolve(catalog, root, spec) do
        {:ok, column} -> {:cont, {:ok, [column | acc]}}
        {:error, reason} -> {:halt, {:error, {spec, reason}}}
      end
    end)
    |> case do
      {:ok, columns} -> {:ok, Enum.reverse(columns)}
      error -> error
    end
  end

  @doc """
  Columns a person could add, ranked against what they typed.

  Walks every path of up to three links from the root, through visible
  tables only, and offers each reachable field, plus the rollups a many-link
  allows: a count, the numeric aggregates of number fields, `list` of text
  and enum fields, `latest` where the table has a time field. An empty query
  ranks by path depth, so the root's own fields come first.
  """
  @spec suggest(t(), Table.t(), String.t(), keyword()) :: [Column.t()]
  def suggest(%__MODULE__{} = catalog, %Table{} = root, text, opts \\ []) do
    exclude = opts |> Keyword.get(:exclude, []) |> MapSet.new()
    limit = Keyword.get(opts, :limit, @max_suggestions)
    tokens = text |> String.downcase() |> String.split(~r/[\s.:>›]+/, trim: true)

    catalog
    |> candidate_specs(root)
    |> Enum.reject(&MapSet.member?(exclude, &1))
    |> Enum.flat_map(fn spec ->
      case resolve(catalog, root, spec) do
        {:ok, column} -> [column]
        {:error, _reason} -> []
      end
    end)
    |> Enum.map(&{score(&1, tokens), &1})
    |> Enum.reject(fn {score, _column} -> tokens != [] and score == 0 end)
    |> Enum.sort_by(fn {score, column} -> {-score, column.depth, column.label} end)
    |> Enum.take(limit)
    |> Enum.map(fn {_score, column} -> column end)
  end

  defp candidate_specs(catalog, root) do
    field_specs(root, "") ++ link_specs(catalog, root, "", 1)
  end

  defp field_specs(%Table{} = table, prefix) do
    table |> Table.visible_fields() |> Enum.map(&(prefix <> &1.id))
  end

  defp link_specs(_catalog, _table, _prefix, depth) when depth > 3, do: []

  defp link_specs(catalog, %Table{} = table, prefix, depth) do
    table
    |> Table.links()
    |> Enum.flat_map(fn %Link{} = link ->
      case fetch_table(catalog, link.to) do
        {:ok, target} ->
          path = prefix <> link.id

          case link.kind do
            :one ->
              field_specs(target, path <> ".") ++
                link_specs(catalog, target, path <> ".", depth + 1)

            :many ->
              rollup_specs(target, path)
          end

        :error ->
          []
      end
    end)
  end

  defp rollup_specs(%Table{} = target, path) do
    fields = Table.visible_fields(target)

    numeric =
      fields
      |> Enum.filter(&(&1.type in [:integer, :float, :decimal]))
      |> Enum.reject(&(&1.id == target.key))
      |> Enum.flat_map(fn field ->
        for agg <- [:sum, :avg, :min, :max], do: "#{path}.#{field.id}:#{agg}"
      end)

    dated =
      fields
      |> Enum.filter(&(&1.type in [:date, :datetime]))
      |> Enum.flat_map(fn field -> ["#{path}.#{field.id}:min", "#{path}.#{field.id}:max"] end)

    listed =
      fields
      |> Enum.filter(&(&1.type in [:string, :enum]))
      |> Enum.map(&"#{path}.#{&1.id}:list")

    latest =
      if target.time_field do
        fields
        |> Enum.reject(&(&1.id == target.key))
        |> Enum.map(&"#{path}.#{&1.id}:latest")
      else
        []
      end

    ["#{path}:count"] ++ numeric ++ dated ++ listed ++ latest
  end

  # Every token must be found somewhere in the label or the spec; a match on
  # the field's own name counts more than one on a link it is reached through.
  defp score(%Column{}, []), do: 1

  defp score(%Column{} = column, tokens) do
    haystack = String.downcase(column.label <> " " <> column.spec)
    short = String.downcase(column.short_label)

    if Enum.all?(tokens, &String.contains?(haystack, &1)) do
      Enum.reduce(tokens, 1, fn token, acc ->
        cond do
          String.starts_with?(short, token) -> acc + 4
          String.contains?(short, token) -> acc + 2
          true -> acc + 1
        end
      end)
    else
      0
    end
  end
end
