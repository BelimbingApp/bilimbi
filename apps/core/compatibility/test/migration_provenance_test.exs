defmodule Bilimbi.Core.Compatibility.MigrationProvenanceTest do
  # A mounted Domain is its own Git repository under apps/domains/. Each test
  # mounts a throwaway one through `InProcessDomain`, which loads it the way
  # a build of the host would and unmounts it by unloading its application
  # and deleting its checkout and build output. Nothing is mounted in the
  # real checkout.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.InProcessDomain
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Ecto.Adapters.SQL

  @version 20_991_002_000_001
  @otp_app InProcessDomain.otp_app()

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
    schema = "bilimbi_provenance_#{System.system_time(:microsecond)}_#{suffix}"
    SQL.query!(MigrationTestRepo, "CREATE SCHEMA #{quote!(schema)}", [])

    root = Path.join(System.tmp_dir!(), "bilimbi-provenance-#{suffix}")

    on_exit(fn ->
      unmount!(root)
      File.rm_rf!(root)

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Bilimbi.Base.Repo, fn ->
        SQL.query!(Bilimbi.Base.Repo, "DROP SCHEMA IF EXISTS #{quote!(schema)} CASCADE", [])
      end)
    end)

    %{schema: schema, root: root, suffix: suffix}
  end

  test "a mounted Domain's table and rows survive unmount, clean rebuild, and remount", context do
    %{schema: schema} = context

    mount!(context)
    assert @version in Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)

    SQL.query!(
      MigrationTestRepo,
      "INSERT INTO #{quote!(schema)}.proof_factory_rows (label) VALUES ('survives-unmount')",
      []
    )

    unmount!(context.root)
    refute Enum.any?(ModuleRegistry.installed_modules!(), &(&1.otp_app == @otp_app))

    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == []
    assert :ok = Compatibility.verify(MigrationTestRepo, prefix: schema)
    assert {:ok, :already_adopted} = Compatibility.adopt(MigrationTestRepo, prefix: schema)
    assert rows(schema) == ["survives-unmount"]
    assert Enum.count(recorded_versions(schema), &(&1 == @version)) == 1

    mount!(context)
    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == []
    assert rows(schema) == ["survives-unmount"]
    assert Enum.count(recorded_versions(schema), &(&1 == @version)) == 1
  end

  test "a retired version with no retained provenance is still refused", context do
    %{schema: schema} = context

    mount!(context)
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    delete_provenance!(schema)
    unmount!(context.root)

    assert_raise ArgumentError,
                 ~r/version #{@version} is recorded but no installed module owns it/,
                 fn ->
                   Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
                 end

    ledger = recorded_versions(schema)

    assert {:error, {:ledger_conflict, ^ledger}} =
             Compatibility.adopt(MigrationTestRepo, prefix: schema)
  end

  test "only a Domain or Extension owner may be absent from the installed graph", context do
    %{schema: schema} = context

    mount!(context)
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    unmount!(context.root)

    SQL.query!(
      MigrationTestRepo,
      "UPDATE #{quote!(schema)}.bilimbi_migration_provenance SET owner_layer = 'core' WHERE version = $1",
      [@version]
    )

    assert_raise ArgumentError, ~r/only a Domain or Extension can be unmounted/, fn ->
      Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    end
  end

  test "a remount that ships a different migration under an applied version is refused",
       context do
    %{schema: schema} = context

    mount!(context)
    Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    unmount!(context.root)

    mount!(context, column: :note)

    assert_raise ArgumentError,
                 ~r/version #{@version} of proof_factory\/widget differs from the file that was applied/,
                 fn -> Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) end

    unmount!(context.root)
    mount!(context, id: "proof_factory/gadget")

    assert_raise ArgumentError,
                 ~r/was applied by proof_factory\/widget \(domain\), but proof_factory\/gadget \(domain\) ships it/,
                 fn -> Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) end
  end

  test "a migration that committed before a later one failed keeps its provenance", context do
    %{schema: schema} = context

    mount!(context, failing: true)

    assert_raise RuntimeError, ~r/proof factory migration failed/, fn ->
      Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false)
    end

    assert @version in recorded_versions(schema)
    refute (@version + 1) in recorded_versions(schema)
    assert provenance_owner(schema, @version) == ["proof_factory/widget"]

    unmount!(context.root)
    assert Compatibility.migrate(MigrationTestRepo, prefix: schema, log: false) == []
  end

  defp mount!(context, opts \\ []) do
    column = Keyword.get(opts, :column, :label)

    migrations =
      [
        {@version, :bilimbi_only, "CreateRows#{column}",
         InProcessDomain.create_table(:proof_factory_rows, column)}
      ] ++
        if Keyword.get(opts, :failing, false),
          do: [
            {@version + 1, :bilimbi_only, "Fail",
             InProcessDomain.failing("proof factory migration failed")}
          ],
          else: []

    InProcessDomain.mount!(context,
      id: Keyword.get(opts, :id, InProcessDomain.id()),
      migrations: migrations
    )
  end

  defp unmount!(root), do: InProcessDomain.unmount!(root)

  defp delete_provenance!(schema) do
    SQL.query!(
      MigrationTestRepo,
      "DELETE FROM #{quote!(schema)}.bilimbi_migration_provenance WHERE version = $1",
      [@version]
    )
  end

  defp provenance_owner(schema, version) do
    SQL.query!(
      MigrationTestRepo,
      "SELECT owner_id FROM #{quote!(schema)}.bilimbi_migration_provenance WHERE version = $1",
      [version]
    ).rows
    |> List.flatten()
  end

  defp rows(schema) do
    SQL.query!(MigrationTestRepo, "SELECT label FROM #{quote!(schema)}.proof_factory_rows", []).rows
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

  defp quote!(identifier), do: SchemaVerifier.quote_identifier!(identifier)
end
