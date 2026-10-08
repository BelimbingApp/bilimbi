defmodule Bilimbi.Core.Compatibility.MountedDomainAdoptionTest do
  # A Domain maps a Belimbing module an installation may never have had, and
  # it may be mounted before the first adoption or long after the Platform
  # migrated. Each test mounts a throwaway Domain through `InProcessDomain`
  # beside the installed Platform, with migrations dated before every
  # Platform migration, as Factory's are before the Platform versions an
  # adopted installation has already recorded.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.InProcessDomain
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Ecto.Adapters.SQL

  @baseline 20_260_101_000_000
  @bilimbi_only 20_260_101_000_001
  @baseline_table "proof_factory_entries"
  @second_table "proof_factory_labels"
  @bilimbi_only_table "proof_factory_rows"

  setup do
    repo_options =
      Bilimbi.Base.Repo.config()
      |> Keyword.put(:name, MigrationTestRepo)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)

    Application.put_env(:bilimbi_base_database, MigrationTestRepo, repo_options)
    on_exit(fn -> Application.delete_env(:bilimbi_base_database, MigrationTestRepo) end)
    start_supervised!(MigrationTestRepo)

    suffix = System.unique_integer([:positive, :monotonic])
    schema = "bilimbi_mounted_#{System.system_time(:microsecond)}_#{suffix}"
    SQL.query!(MigrationTestRepo, "CREATE SCHEMA #{quote!(schema)}", [])

    root = Path.join(System.tmp_dir!(), "bilimbi-mounted-#{suffix}")

    on_exit(fn ->
      InProcessDomain.unmount!(root)
      File.rm_rf!(root)

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Bilimbi.Base.Repo, fn ->
        SQL.query!(Bilimbi.Base.Repo, "DROP SCHEMA IF EXISTS #{quote!(schema)} CASCADE", [])
      end)
    end)

    # The Platform's own baselines, read before any Domain joins the graph.
    %{
      schema: schema,
      root: root,
      suffix: suffix,
      platform_baselines: Compatibility.baseline_versions()
    }
  end

  describe "mounted before adoption on a database that never had its Belimbing table" do
    test "verification passes, adoption leaves the baseline pending, and migrate creates it",
         context do
      %{schema: schema, platform_baselines: platform_baselines} = context
      belimbing_database!(schema)
      mount!(context)

      assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)

      assert Compatibility.absent_modules(MigrationTestRepo, prefix: schema) == [
               InProcessDomain.id()
             ]

      assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
      assert recorded_versions(schema) == platform_baselines
      refute relation?(schema, @baseline_table)

      applied = Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
      assert [@baseline, @bilimbi_only | platform_pending] = applied
      assert platform_pending == Compatibility.migration_entries() |> pending_platform_versions()

      assert relation?(schema, @baseline_table)
      assert relation?(schema, @bilimbi_only_table)
      assert provenance_owner(schema, @baseline) == [InProcessDomain.id()]
      assert Compatibility.absent_modules(MigrationTestRepo, prefix: schema) == []
      assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
      assert {:ok, :already_adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
      assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == []
    end

    test "a Domain with one of its tables present is drift, not absent", context do
      %{schema: schema} = context
      belimbing_database!(schema)
      mount!(context, tables: [@baseline_table, @second_table])

      SQL.query!(
        MigrationTestRepo,
        "CREATE TABLE #{quote!(schema)}.#{@baseline_table} (id bigserial PRIMARY KEY, label varchar(255) NOT NULL)",
        []
      )

      expected = ["missing table #{schema}.#{@second_table}"]
      assert {:error, ^expected} = Compatibility.verify(MigrationTestRepo, prefix: schema)
      assert Compatibility.absent_modules(MigrationTestRepo, prefix: schema) == []

      assert {:error, {:schema_drift, ^expected}} =
               Compatibility.adopt(MigrationTestRepo, prefix: schema)

      refute relation?(schema, "bilimbi_schema_migrations")
    end

    test "a present table that differs from the contract is drift", context do
      %{schema: schema} = context
      belimbing_database!(schema)
      mount!(context)

      SQL.query!(
        MigrationTestRepo,
        "CREATE TABLE #{quote!(schema)}.#{@baseline_table} (id bigserial PRIMARY KEY)",
        []
      )

      expected = ["#{@baseline_table}: missing column label"]
      assert {:error, ^expected} = Compatibility.verify(MigrationTestRepo, prefix: schema)

      assert {:error, {:schema_drift, ^expected}} =
               Compatibility.adopt(MigrationTestRepo, prefix: schema)
    end

    test "a Domain's contribution found on another table makes it present", context do
      %{schema: schema} = context
      belimbing_database!(schema)

      # A table outside every installed contract, as a Belimbing module Bilimbi
      # does not map leaves behind, carrying an index the Domain contributes.
      SQL.query!(
        MigrationTestRepo,
        "CREATE TABLE #{quote!(schema)}.proof_factory_host (id bigserial PRIMARY KEY, label varchar(255))",
        []
      )

      SQL.query!(
        MigrationTestRepo,
        "CREATE INDEX proof_factory_host_label_index ON #{quote!(schema)}.proof_factory_host (label)",
        []
      )

      mount!(context,
        contributions: [
          %{
            name: "proof_factory_host",
            indexes: %{
              "proof_factory_host_label_index" => %{columns: ["label"], unique: false, where: nil}
            }
          }
        ]
      )

      expected = ["missing table #{schema}.#{@baseline_table}"]
      assert {:error, ^expected} = Compatibility.verify(MigrationTestRepo, prefix: schema)
      assert Compatibility.absent_modules(MigrationTestRepo, prefix: schema) == []
    end
  end

  describe "mounted after the Platform migrated" do
    test "its earlier-dated migrations run and are recorded on a fresh installation", context do
      %{schema: schema} = context
      Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
      platform_versions = recorded_versions(schema)
      assert Enum.max(platform_versions) > @bilimbi_only

      mount!(context)

      assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) ==
               [@baseline, @bilimbi_only]

      assert recorded_versions(schema) ==
               Enum.sort([@baseline, @bilimbi_only | platform_versions])

      assert relation?(schema, @baseline_table)
      assert relation?(schema, @bilimbi_only_table)
      assert provenance_owner(schema, @bilimbi_only) == [InProcessDomain.id()]
      assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
      assert {:ok, :already_adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
      assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == []
    end

    test "an adopted installation takes the Domain the same way", context do
      %{schema: schema, platform_baselines: platform_baselines} = context
      belimbing_database!(schema)
      assert {:ok, :adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
      Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
      platform_versions = recorded_versions(schema)
      assert platform_baselines -- platform_versions == []

      mount!(context)

      assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
      assert {:ok, :already_adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
      assert recorded_versions(schema) == platform_versions

      assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) ==
               [@baseline, @bilimbi_only]

      assert relation?(schema, @baseline_table)
      assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    end

    test "a gap inside one owner's own sequence is still refused", context do
      %{schema: schema} = context
      Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

      mount!(context,
        bilimbi_only: [
          {@bilimbi_only, "CreateRows", @bilimbi_only_table},
          {@bilimbi_only + 1, "CreateMore", "proof_factory_more"}
        ]
      )

      Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

      SQL.query!(
        MigrationTestRepo,
        "DELETE FROM #{quote!(schema)}.bilimbi_schema_migrations WHERE version = $1",
        [@bilimbi_only]
      )

      assert_raise ArgumentError,
                   ~r/recorded bilimbi_only versions \[#{@bilimbi_only + 1}\] of proof_factory\/widget are not a prefix/,
                   fn -> Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) end

      ledger = recorded_versions(schema)

      assert {:error, {:ledger_conflict, ^ledger}} =
               Compatibility.adopt(MigrationTestRepo, prefix: schema)
    end
  end

  # An existing Belimbing database: every Platform baseline's structure and
  # no Bilimbi ledger or provenance. Run before the Domain is mounted, so
  # its Belimbing table was never created.
  defp belimbing_database!(schema) do
    Compatibility.migrate_baseline(MigrationTestRepo, prefix: schema, log: false)
    SQL.query!(MigrationTestRepo, "DROP TABLE #{quote!(schema)}.bilimbi_schema_migrations", [])
    SQL.query!(MigrationTestRepo, "DROP TABLE #{quote!(schema)}.bilimbi_migration_provenance", [])
  end

  defp mount!(context, opts \\ []) do
    tables = Keyword.get(opts, :tables, [@baseline_table])

    bilimbi_only =
      Keyword.get(opts, :bilimbi_only, [{@bilimbi_only, "CreateRows", @bilimbi_only_table}])

    migrations =
      [{@baseline, :compatible_baseline, "CreateEntries", InProcessDomain.create_tables(tables)}] ++
        for {version, name, table} <- bilimbi_only do
          {version, :bilimbi_only, name, InProcessDomain.create_table(table)}
        end

    InProcessDomain.mount!(context,
      migrations: migrations,
      contract: %{
        tables: Enum.map(tables, &InProcessDomain.table_spec/1),
        contributions: Keyword.get(opts, :contributions, [])
      }
    )
  end

  defp pending_platform_versions(entries) do
    for {version, _module, :bilimbi_only} <- entries, version not in [@baseline, @bilimbi_only] do
      version
    end
  end

  defp provenance_owner(schema, version) do
    SQL.query!(
      MigrationTestRepo,
      "SELECT owner_id FROM #{quote!(schema)}.bilimbi_migration_provenance WHERE version = $1",
      [version]
    ).rows
    |> List.flatten()
  end

  defp recorded_versions(schema) do
    SQL.query!(
      MigrationTestRepo,
      "SELECT version FROM #{quote!(schema)}.bilimbi_schema_migrations ORDER BY version",
      []
    ).rows
    |> List.flatten()
  end

  defp relation?(schema, table) do
    [[relation]] =
      SQL.query!(MigrationTestRepo, "SELECT to_regclass($1)::text", ["#{schema}.#{table}"]).rows

    relation != nil
  end

  defp quote!(identifier), do: SchemaVerifier.quote_identifier!(identifier)
end
