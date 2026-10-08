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
  alias Bilimbi.Core.Compatibility.MigrationProvenance
  alias Ecto.Adapters.SQL

  @compatibility_source "e70b4d33c0b10790e681f4c2b5095d85a53bc918"

  @doc "The name of Bilimbi's own migration ledger table (`bilimbi_schema_migrations`)."
  @spec migration_source() :: String.t()
  def migration_source, do: migration_source(Repo)

  @doc "The Belimbing merge commit whose schema is the compatibility reference."
  @spec compatibility_source() :: String.t()
  def compatibility_source, do: @compatibility_source

  @doc "The migration directories of every installed module, in Base, Core, Domain, Extension order."
  @spec migration_paths() :: [String.t()]
  def migration_paths, do: ModuleRegistry.migration_paths!()

  @doc "The versions of the installed migrations classed `:compatible_baseline`."
  @spec baseline_versions() :: [integer()]
  def baseline_versions, do: baseline_versions(installed_migrations())

  @doc "Every installed migration as `{version, module, disposition}`, in version order."
  @spec migration_entries() :: [{integer(), module(), :compatible_baseline | :bilimbi_only}]
  def migration_entries do
    Enum.map(installed_migrations(), &{&1.version, &1.module, &1.disposition})
  end

  # Every installed migration with the descriptor that owns it, in version
  # order. Provenance needs the owner and the file, not only the version.
  defp installed_migrations do
    migrations =
      ModuleRegistry.migration_modules!()
      |> Enum.flat_map(fn descriptor ->
        descriptor.otp_app
        |> Application.app_dir(descriptor.migrations)
        |> Path.join("*.exs")
        |> Path.wildcard()
        |> Enum.map(fn path ->
          Code.require_file(path)
          version = migration_version!(path)

          %{
            version: version,
            module: migration_module!(path),
            disposition: Map.fetch!(descriptor.migration_dispositions, version),
            owner_id: descriptor.id,
            owner_layer: descriptor.layer,
            checksum: MigrationProvenance.checksum(path)
          }
        end)
      end)
      |> Enum.sort_by(& &1.version)

    versions = Enum.map(migrations, & &1.version)

    case versions -- Enum.uniq(versions) do
      [] -> migrations
      duplicates -> raise ArgumentError, "duplicate migration versions: #{inspect(duplicates)}"
    end
  end

  @doc """
  Runs every installed migration through the single ledger and records provenance.

  A ledger whose recorded versions are not class-valid raises `ArgumentError`.
  """
  @spec migrate(Ecto.Repo.t(), keyword()) :: [integer()]
  def migrate(repo \\ Repo, opts \\ []) do
    installed = installed_migrations()
    schema = Keyword.get(opts, :prefix, "public")
    _ = SchemaVerifier.quote_identifier!(schema)

    strict_version_order = strict_version_order?(repo, schema, installed)

    opts =
      opts
      |> Keyword.put(:all, true)
      |> Keyword.put(:strict_version_order, strict_version_order)

    run_and_record(repo, schema, installed, opts)
  end

  @doc """
  Whether the schema holds a Belimbing database that Bilimbi has not adopted:
  Laravel's `migrations` table exists but the Bilimbi ledger is missing or
  empty. Migrating such a database would run baseline DDL against tables that
  already exist, so a deployment must adopt it first.

  Only `migrations` and the ledger are read; adoption itself decides whether
  the schema is compatible.
  """
  @spec unadopted_belimbing?(Ecto.Repo.t(), keyword()) :: boolean()
  def unadopted_belimbing?(repo \\ Repo, opts \\ []) do
    schema = Keyword.get(opts, :prefix, "public")
    quoted = SchemaVerifier.quote_identifier!(schema)

    [[laravel]] = SQL.query!(repo, "SELECT to_regclass($1)::text", ["#{quoted}.migrations"]).rows
    not is_nil(laravel) and ledger_versions(repo, schema) in [:missing, []]
  end

  @doc """
  Raises unless `migrate/2` is safe: refuses an unadopted Belimbing database
  and names the adoption sequence.
  """
  @spec ensure_adopted!(Ecto.Repo.t(), keyword()) :: :ok
  def ensure_adopted!(repo \\ Repo, opts \\ []) do
    if unadopted_belimbing?(repo, opts) do
      raise ArgumentError,
            "this is an existing Belimbing database that Bilimbi has not adopted; " <>
              "refusing to migrate. Run verify, adopt, remap (dry run, then real) before migrate " <>
              "(docs/migrating-from-belimbing.md)"
    end

    :ok
  end

  defp run_and_record(repo, schema, installed, opts) do
    migrations = Enum.map(installed, &{&1.version, &1.module})

    try do
      Ecto.Migrator.run(repo, migrations, :up, opts)
    after
      case ledger_versions(repo, schema) do
        :missing -> :ok
        versions -> MigrationProvenance.record!(repo, schema, installed, versions)
      end
    end
  end

  @doc """
  Runs only the `:compatible_baseline` migrations, for building the reference
  schema before adoption.
  """
  @spec migrate_baseline(Ecto.Repo.t(), keyword()) :: [integer()]
  def migrate_baseline(repo \\ Repo, opts \\ []) do
    baselines = Enum.filter(installed_migrations(), &(&1.disposition == :compatible_baseline))
    schema = Keyword.get(opts, :prefix, "public")
    _ = SchemaVerifier.quote_identifier!(schema)

    opts =
      opts
      |> Keyword.put(:all, true)
      |> Keyword.put(:strict_version_order, false)

    run_and_record(repo, schema, baselines, opts)
  end

  @doc """
  Verifies the live schema against every installed module's schema contract and
  live-data invariants.

  Returns `:ok` or `{:error, messages}`.
  """
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

  @doc """
  Adopts an existing Belimbing database: verifies it strictly, then records the
  compatible baselines in the ledger.

  Returns `{:ok, :adopted | :advanced | :already_adopted}`, or an error for
  structural drift or a conflicting ledger.
  """
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
    installed = installed_migrations()

    case ledger_versions(repo, schema) do
      :missing ->
        create_ledger!(repo, schema)
        record_baselines!(repo, schema, installed, [])
        {:ok, :adopted}

      [] ->
        record_baselines!(repo, schema, installed, [])
        {:ok, :adopted}

      versions ->
        case validate_ledger(repo, schema, installed, versions) do
          :ok ->
            if record_baselines!(repo, schema, installed, versions) == [],
              do: {:ok, :already_adopted},
              else: {:ok, :advanced}

          {:error, _conflicts} ->
            repo.rollback({:ledger_conflict, versions})
        end
    end
  end

  # Records the compatible baselines the ledger lacks and the provenance of
  # every applied version, returning the baselines it recorded.
  defp record_baselines!(repo, schema, installed, versions) do
    missing = baseline_versions(installed) -- versions
    if missing != [], do: record_versions!(repo, schema, missing)
    MigrationProvenance.record!(repo, schema, installed, versions ++ missing)
    missing
  end

  defp baseline_versions(installed) do
    for %{disposition: :compatible_baseline, version: version} <- installed, do: version
  end

  defp strict_version_order?(repo, schema, installed) do
    case ledger_versions(repo, schema) do
      :missing ->
        true

      versions ->
        case validate_ledger(repo, schema, installed, versions) do
          :ok ->
            not class_valid_gap?(installed, versions)

          {:error, conflicts} ->
            raise ArgumentError,
                  "Bilimbi migration ledger is not class-valid:\n" <>
                    Enum.map_join(conflicts, "\n", &"  - #{&1}")
        end
    end
  end

  # Every recorded version must be explained -- by an installed migration or,
  # for a Domain or Extension that has since been unmounted, by retained
  # provenance -- and the installed versions recorded in each class must be a
  # prefix of that class's sequence.
  defp validate_ledger(repo, schema, installed, versions) do
    installed_ids = Enum.map(ModuleRegistry.installed_modules!(), & &1.id)
    provenance = MigrationProvenance.fetch(repo, schema)

    conflicts =
      MigrationProvenance.conflicts(installed, versions, provenance, installed_ids) ++
        class_conflicts(installed, versions, :compatible_baseline) ++
        class_conflicts(installed, versions, :bilimbi_only)

    if conflicts == [], do: :ok, else: {:error, conflicts}
  end

  defp class_conflicts(installed, versions, disposition) do
    class_versions = for %{disposition: ^disposition, version: v} <- installed, do: v
    recorded = Enum.filter(class_versions, &(&1 in versions))

    if prefix?(class_versions, recorded),
      do: [],
      else: [
        "recorded #{disposition} versions #{inspect(recorded)} are not a prefix of #{inspect(class_versions)}"
      ]
  end

  defp prefix?(versions, recorded) do
    Enum.take(versions, length(recorded)) == recorded
  end

  defp class_valid_gap?(_entries, []), do: false

  defp class_valid_gap?(installed, versions) do
    latest_recorded = Enum.max(versions)
    Enum.any?(installed, &(&1.version < latest_recorded and &1.version not in versions))
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

    # A raw table name rather than an Ecto schema, which is also why the
    # repo's write capture leaves it alone: the migration ledger is
    # lifecycle bookkeeping, not business data (ADR 0002, ADR 0013).
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
