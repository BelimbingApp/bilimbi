defmodule Bilimbi.Core.Compatibility do
  @moduledoc """
  Orchestrates the required Base and Core compatibility schema.

  Fresh databases run the owned Ecto migrations. Existing Belimbing databases
  must pass strict verification before their current state is recorded in
  Bilimbi's independent migration ledger.
  """

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  @compatibility_source "e70b4d33c0b10790e681f4c2b5095d85a53bc918"

  def migration_source, do: migration_source(Repo)
  def compatibility_source, do: @compatibility_source

  def migration_paths, do: ModuleRegistry.migration_paths!()

  def baseline_versions do
    Enum.map(migration_entries(), &elem(&1, 0))
  end

  def migration_entries do
    entries =
      migration_paths()
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.exs")))
      |> Enum.map(fn path ->
        Code.require_file(path)
        {migration_version!(path), migration_module!(path)}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    versions = Enum.map(entries, &elem(&1, 0))

    case versions -- Enum.uniq(versions) do
      [] -> entries
      duplicates -> raise ArgumentError, "duplicate migration versions: #{inspect(duplicates)}"
    end
  end

  @spec migrate(Ecto.Repo.t(), keyword()) :: [integer()]
  def migrate(repo \\ Repo, opts \\ []) do
    opts = opts |> Keyword.put(:all, true) |> Keyword.put(:strict_version_order, true)
    Ecto.Migrator.run(repo, migration_entries(), :up, opts)
  end

  @spec verify(Ecto.Repo.t(), keyword()) :: :ok | {:error, [String.t()]}
  def verify(repo \\ Repo, opts \\ []) do
    contracts =
      ModuleRegistry.installed_modules!()
      |> Enum.reject(&is_nil(&1.schema_contract))
      |> Enum.map(& &1.schema_contract)

    table_specs = Enum.flat_map(contracts, & &1.tables())

    contributions =
      Enum.flat_map(contracts, fn contract ->
        if function_exported?(contract, :contributions, 0),
          do: contract.contributions(),
          else: []
      end)

    with :ok <- SchemaVerifier.verify(repo, table_specs, opts),
         :ok <- SchemaVerifier.verify_contributions(repo, contributions, opts) do
      verify_invariants(contracts, repo, opts)
    end
  end

  @spec adopt(Ecto.Repo.t(), keyword()) ::
          {:ok, :adopted | :advanced | :already_adopted}
          | {:error, {:schema_drift, [String.t()]} | {:ledger_conflict, [integer()]}}
  def adopt(repo \\ Repo, opts \\ []) do
    schema = Keyword.get(opts, :prefix, "public")
    # Validate the schema identifier early for a clean failure before the
    # transaction starts. The shared quoter re-validates as it builds SQL.
    _ = SchemaVerifier.quote_identifier!(schema)

    case repo.transaction(fn -> adopt_in_transaction(repo, schema, opts) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp adopt_in_transaction(repo, schema, opts) do
    SQL.query!(
      repo,
      "SELECT pg_advisory_xact_lock(hashtext($1))",
      ["bilimbi-schema-adoption:#{schema}"]
    )

    case verify(repo, opts) do
      :ok -> adopt_ledger(repo, schema)
      {:error, errors} -> repo.rollback({:schema_drift, errors})
    end
  end

  defp adopt_ledger(repo, schema) do
    case ledger_versions(repo, schema) do
      :missing ->
        create_ledger!(repo, schema)
        record_versions!(repo, schema, baseline_versions())
        {:ok, :adopted}

      [] ->
        record_versions!(repo, schema, baseline_versions())
        {:ok, :adopted}

      versions ->
        adopt_existing_ledger(repo, schema, versions)
    end
  end

  defp adopt_existing_ledger(repo, schema, versions) do
    baselines = baseline_versions()

    cond do
      versions == baselines ->
        {:ok, :already_adopted}

      Enum.take(baselines, length(versions)) == versions ->
        record_versions!(repo, schema, Enum.drop(baselines, length(versions)))
        {:ok, :advanced}

      true ->
        repo.rollback({:ledger_conflict, versions})
    end
  end

  defp ledger_versions(repo, schema) do
    migration_source = migration_source(repo)
    qualified_name = "#{schema}.#{migration_source}"

    case SQL.query!(repo, "SELECT to_regclass($1)::text", [qualified_name]).rows do
      [[nil]] ->
        :missing

      [[_table]] ->
        result =
          SQL.query!(
            repo,
            "SELECT version FROM #{SchemaVerifier.quote_identifier!(schema)}.#{SchemaVerifier.quote_identifier!(migration_source)} ORDER BY version",
            []
          )

        Enum.map(result.rows, fn [version] -> version end)
    end
  end

  defp create_ledger!(repo, schema) do
    migration_source = migration_source(repo)

    SQL.query!(
      repo,
      """
      CREATE TABLE #{SchemaVerifier.quote_identifier!(schema)}.#{SchemaVerifier.quote_identifier!(migration_source)} (
        version bigint PRIMARY KEY,
        inserted_at timestamp(0) without time zone NOT NULL
      )
      """,
      []
    )
  end

  defp record_versions!(repo, schema, versions) do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    rows = Enum.map(versions, &%{version: &1, inserted_at: now})

    {count, _} = repo.insert_all(migration_source(repo), rows, prefix: schema)

    if count != length(versions) do
      repo.rollback({:ledger_conflict, ledger_versions(repo, schema)})
    end
  end

  defp verify_invariants(contracts, repo, opts) do
    errors =
      contracts
      |> Enum.flat_map(fn contract ->
        if function_exported?(contract, :verify_invariants, 2) do
          case contract.verify_invariants(repo, opts) do
            :ok -> []
            {:error, errors} -> errors
          end
        else
          []
        end
      end)
      |> Enum.sort()

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp migration_source(repo) do
    repo.config()
    |> Keyword.fetch!(:migration_source)
  end

  defp migration_version!(path) do
    case Regex.run(~r/^(\d+)_.*\.exs$/, Path.basename(path), capture: :all_but_first) do
      [version] -> String.to_integer(version)
      _other -> raise ArgumentError, "invalid migration filename: #{path}"
    end
  end

  defp migration_module!(path) do
    with {:ok, source} <- File.read(path),
         {:ok, syntax} <- Code.string_to_quoted(source),
         {:ok, module} <- top_level_module(syntax) do
      module
    else
      _other -> raise ArgumentError, "migration file must define one top-level module: #{path}"
    end
  end

  defp top_level_module({:defmodule, _metadata, [module_ast, _body]}) do
    {:ok, Macro.expand(module_ast, __ENV__)}
  end

  defp top_level_module({:__block__, _metadata, expressions}) do
    case Enum.filter(expressions, &match?({:defmodule, _, _}, &1)) do
      [module_definition] -> top_level_module(module_definition)
      _other -> :error
    end
  end

  defp top_level_module(_syntax), do: :error
end
