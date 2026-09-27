defmodule Bilimbi.Base.Grid.Catalog do
  @moduledoc """
  The tables one account may read, and the paths between them.

  `for_scope/1` reads the installed contribution snapshot once and keeps
  only the tables whose capability the scope's actor holds, so a catalog is
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

    visible =
      tables
      |> Enum.filter(fn {_id, table} -> table.capability in allowed end)
      |> Map.new()

    %__MODULE__{scope: scope, tables: visible}
  end

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

  @doc "The visible tables, by label."
  @spec tables(t()) :: [Table.t()]
  def tables(%__MODULE__{tables: tables}), do: tables |> Map.values() |> Enum.sort_by(& &1.label)

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

  @doc "The root table's own visible fields as columns, the grid's starting point."
  @spec default_columns(t(), Table.t()) :: [Column.t()]
  def default_columns(%__MODULE__{} = catalog, %Table{} = root) do
    root
    |> Table.visible_fields()
    |> Enum.map(& &1.id)
    |> then(&resolve_all(catalog, root, &1))
    |> case do
      {:ok, columns} -> columns
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

  @doc "The root field a search box matches against: every searchable string field."
  @spec search_fields(Table.t()) :: [Field.t()]
  def search_fields(%Table{} = table) do
    table
    |> Table.visible_fields()
    |> Enum.filter(&(&1.searchable and &1.type in [:string, :enum]))
  end
end
