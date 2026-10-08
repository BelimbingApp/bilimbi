defmodule Bilimbi.Core.Compatibility do
  @moduledoc """
  Orchestrates the required Base and Core compatibility schema.

  Fresh databases run the owned Ecto migrations. Existing Belimbing databases
  must pass strict verification before their current state is recorded in
  Bilimbi's independent migration ledger.

  A mounted Domain or Extension maps a Belimbing module an installation may
  never have had. One whose owned structure is wholly absent is not drift:
  verification and adoption leave its compatible baselines pending, and
  `migrate/2` creates them as on a fresh database (`absent_modules/2`). The
  Platform maps Belimbing's own tables, so a Platform module with none is a
  database behind the compatibility source, and a partly present owner of
  any layer is drift.
  """

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility.MigrationProvenance
  alias Ecto.Adapters.SQL

  @compatibility_source "e70b4d33c0b10790e681f4c2b5095d85a53bc918"
  @optional_layers [:domain, :extension]

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
  Runs every pending installed migration through the single ledger and
  records provenance.

  A ledger that is not valid for every owner raises `ArgumentError`. Pending
  migrations run in version order among themselves; one dated before a
  recorded version is expected when a Domain or Extension was mounted after
  the Platform migrated, when adoption left an absent owner's baseline for
  this command, or when a later compatible baseline was adopted while an
  earlier Bilimbi-only migration was pending. `Ecto.Migrator.run/4` never
  refuses such a version itself; the ledger validation here is the guard.
  """
  @spec migrate(Ecto.Repo.t(), keyword()) :: [integer()]
  def migrate(repo \\ Repo, opts \\ []) do
    installed = installed_migrations()
    schema = Keyword.get(opts, :prefix, "public")
    _ = SchemaVerifier.quote_identifier!(schema)
    validate_ledger!(repo, schema, installed)
    run_and_record(repo, schema, installed, Keyword.put(opts, :all, true))
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
    run_and_record(repo, schema, baselines, Keyword.put(opts, :all, true))
  end

  @doc """
  Verifies the live schema against every installed module's schema contract and
  live-data invariants.

  An absent Domain or Extension (`absent_modules/2`) is skipped: it has no
  structure to verify and no invariant to hold. Returns `:ok` or
  `{:error, messages}`.
  """
  @spec verify(Ecto.Repo.t(), keyword()) :: :ok | {:error, [String.t()]}
  def verify(repo \\ Repo, opts \\ []) do
    case verification(repo, opts) do
      {:ok, _absent} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  The stable IDs of the installed Domain or Extension modules whose owned
  structure is wholly absent from the database.

  The Belimbing module such an owner maps was never installed there, so
  verification does not report its tables as missing, adoption leaves its
  compatible baselines unrecorded, and `migrate/2` creates them. An owner
  with a recorded version is never absent: its structure was applied, and a
  table missing afterwards is drift.
  """
  @spec absent_modules(Ecto.Repo.t(), keyword()) :: [String.t()]
  def absent_modules(repo \\ Repo, opts \\ []) do
    for {descriptor, :absent} <- owners_by_presence(repo, opts), do: descriptor.id
  end

  @doc """
  One line per absent module, for the verify, adopt, and release commands to
  print after success, so the operator knows which compatible baselines the
  migrate command will create rather than adopt.
  """
  @spec absent_module_report(Ecto.Repo.t(), keyword()) :: [String.t()]
  def absent_module_report(repo \\ Repo, opts \\ []) do
    for id <- absent_modules(repo, opts) do
      "#{id}: no owned structure exists in this database; " <>
        "the migrate command creates its compatible baseline."
    end
  end

  defp verification(repo, opts) do
    owners = owners_by_presence(repo, opts)
    present = for {descriptor, :present} <- owners, do: descriptor.schema_contract
    absent = for {descriptor, :absent} <- owners, do: descriptor.id
    table_specs = Enum.flat_map(present, & &1.tables())
    contributions = Enum.flat_map(present, &contributions/1)

    with :ok <- SchemaVerifier.verify(repo, table_specs, opts),
         :ok <- SchemaVerifier.verify_contributions(repo, contributions, opts),
         :ok <- verify_invariants(present, repo, opts) do
      {:ok, absent}
    end
  end

  # Every installed module with a schema contract, and whether its owned
  # structure is present or absent. Only a Domain or Extension with no
  # recorded version can be absent: the Platform maps Belimbing's own tables,
  # so a Platform module with none is a database behind the compatibility
  # source, which verification then reports table by table.
  defp owners_by_presence(repo, opts) do
    schema = Keyword.get(opts, :prefix, "public")
    _ = SchemaVerifier.quote_identifier!(schema)

    recorded =
      case ledger_versions(repo, schema) do
        :missing -> []
        versions -> versions
      end

    applied_owners =
      for %{version: version, owner_id: owner_id} <- installed_migrations(),
          version in recorded,
          uniq: true,
          do: owner_id

    ModuleRegistry.installed_modules!()
    |> Enum.reject(&is_nil(&1.schema_contract))
    |> Enum.map(fn descriptor ->
      contract = descriptor.schema_contract

      absent? =
        descriptor.layer in @optional_layers and descriptor.id not in applied_owners and
          SchemaVerifier.absent?(repo, contract.tables(), contributions(contract), opts)

      {descriptor, if(absent?, do: :absent, else: :present)}
    end)
  end

  defp contributions(contract) do
    Code.ensure_loaded!(contract)
    if function_exported?(contract, :contributions, 0), do: contract.contributions(), else: []
  end

  @doc """
  Adopts an existing Belimbing database: verifies it strictly, then records the
  compatible baselines in the ledger.

  The baselines of an absent Domain or Extension (`absent_modules/2`) are
  not recorded: there is nothing to adopt, and `migrate/2` creates them.
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

    case verification(repo, opts) do
      {:ok, absent} -> adopt_ledger(repo, schema, absent)
      {:error, errors} -> repo.rollback({:schema_drift, errors})
    end
  end

  defp adopt_ledger(repo, schema, absent) do
    installed = installed_migrations()
    adoptable = Enum.reject(installed, &(&1.owner_id in absent))

    case ledger_versions(repo, schema) do
      :missing ->
        create_ledger!(repo, schema)
        record_baselines!(repo, schema, installed, adoptable, [])
        {:ok, :adopted}

      [] ->
        record_baselines!(repo, schema, installed, adoptable, [])
        {:ok, :adopted}

      versions ->
        case validate_ledger(repo, schema, installed, versions) do
          :ok ->
            if record_baselines!(repo, schema, installed, adoptable, versions) == [],
              do: {:ok, :already_adopted},
              else: {:ok, :advanced}

          {:error, _conflicts} ->
            repo.rollback({:ledger_conflict, versions})
        end
    end
  end

  # Records the compatible baselines the ledger lacks, except an absent
  # owner's, which stay pending for migrate, and the provenance of every
  # applied version, returning the baselines it recorded.
  defp record_baselines!(repo, schema, installed, adoptable, versions) do
    missing = baseline_versions(adoptable) -- versions
    if missing != [], do: record_versions!(repo, schema, missing)
    MigrationProvenance.record!(repo, schema, installed, versions ++ missing)
    missing
  end

  defp baseline_versions(installed) do
    for %{disposition: :compatible_baseline, version: version} <- installed, do: version
  end

  defp validate_ledger!(repo, schema, installed) do
    case ledger_versions(repo, schema) do
      :missing ->
        :ok

      versions ->
        case validate_ledger(repo, schema, installed, versions) do
          :ok ->
            :ok

          {:error, conflicts} ->
            raise ArgumentError,
                  "Bilimbi migration ledger is not valid:\n" <>
                    Enum.map_join(conflicts, "\n", &"  - #{&1}")
        end
    end
  end

  # Every recorded version must be explained -- by an installed migration or,
  # for a Domain or Extension that has since been unmounted, by retained
  # provenance -- and, for each owner, the recorded versions in each class
  # must be a prefix of that owner's class sequence.
  #
  # Owners are independent of one another: a Domain mounted after the
  # Platform migrated ships earlier-dated versions that are all pending, and
  # a Domain whose Belimbing module an installation never had keeps its
  # baseline pending behind recorded Platform baselines. A gap inside one
  # owner's own sequence, and a ledger no installed module or retained
  # provenance explains, still fail closed.
  defp validate_ledger(repo, schema, installed, versions) do
    installed_ids = Enum.map(ModuleRegistry.installed_modules!(), & &1.id)
    provenance = MigrationProvenance.fetch(repo, schema)

    conflicts =
      MigrationProvenance.conflicts(installed, versions, provenance, installed_ids) ++
        owner_class_conflicts(installed, versions)

    if conflicts == [], do: :ok, else: {:error, conflicts}
  end

  defp owner_class_conflicts(installed, versions) do
    installed
    |> Enum.group_by(&{&1.owner_id, &1.disposition}, & &1.version)
    |> Enum.sort()
    |> Enum.flat_map(fn {{owner_id, disposition}, sequence} ->
      recorded = Enum.filter(sequence, &(&1 in versions))

      if List.starts_with?(sequence, recorded),
        do: [],
        else: [
          "recorded #{disposition} versions #{inspect(recorded)} of #{owner_id} " <>
            "are not a prefix of its sequence #{inspect(sequence)}"
        ]
    end)
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
