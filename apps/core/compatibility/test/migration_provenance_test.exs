defmodule Bilimbi.Core.Compatibility.MigrationProvenanceTest do
  # A mounted Domain is its own Git repository under apps/domains/. Each test
  # builds a throwaway one in a temporary directory, loads it the way a build
  # of the host would, and unmounts it by unloading its application and
  # deleting its checkout and build output. Nothing is mounted in the real
  # checkout.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Core.Compatibility
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Ecto.Adapters.SQL

  @version 20_991_002_000_001
  @otp_app :bilimbi_proof_factory_widget

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

  # Mounts the fixture Domain as its own Git repository and loads its
  # module application the way a host build would: the build directory
  # carries the application, and its priv is the checkout's.
  defp mount!(context, opts \\ []) do
    %{root: root, suffix: suffix} = context
    column = Keyword.get(opts, :column, :label)
    checkout = Path.join(root, "apps/domains/proof_factory")
    module_root = Path.join(checkout, "widget")
    migrations = Path.join(module_root, "priv/repo/migrations")
    File.mkdir_p!(migrations)

    File.write!(
      Path.join(migrations, "#{@version}_create_proof_factory_rows.exs"),
      """
      defmodule Bilimbi.ProofFactory.Widget.Migrations.CreateRows#{suffix}#{column} do
        use Ecto.Migration

        def change do
          create table(:proof_factory_rows) do
            add :#{column}, :string, null: false
          end
        end
      end
      """
    )

    {_output, 0} = System.cmd("git", ["init", "--quiet", checkout])

    build = Path.join(root, "_build/lib/#{@otp_app}")
    File.mkdir_p!(Path.join(build, "ebin"))
    File.ln_s!(Path.join(module_root, "priv"), Path.join(build, "priv"))
    true = Code.prepend_path(Path.join(build, "ebin"))

    installed = ModuleRegistry.installed_modules!()
    [%{graph_fingerprint: fingerprint} | _rest] = installed

    descriptor = %{
      id: Keyword.get(opts, :id, "proof_factory/widget"),
      kind: :module,
      layer: :domain,
      required: false,
      otp_app: @otp_app,
      namespace: Bilimbi.ProofFactory.Widget,
      dependencies: ["base/database"],
      migrations: "priv/repo/migrations",
      migration_dispositions: %{@version => :bilimbi_only},
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil,
      order: length(installed),
      graph_fingerprint: fingerprint
    }

    :ok =
      :application.load(
        {:application, @otp_app,
         [
           description: ~c"proof_factory/widget",
           vsn: ~c"0.1.0",
           modules: [],
           registered: [],
           applications: [:kernel, :stdlib],
           env: [bilimbi_module: descriptor]
         ]}
      )
  end

  # Unmounting removes the checkout and a clean rebuild leaves no build
  # output; the database is never touched.
  defp unmount!(root) do
    _ = Application.unload(@otp_app)
    build = Path.join(root, "_build/lib/#{@otp_app}")
    Code.delete_path(Path.join(build, "ebin"))
    File.rm_rf!(build)
    File.rm_rf!(Path.join(root, "apps/domains/proof_factory"))
  end

  defp delete_provenance!(schema) do
    SQL.query!(
      MigrationTestRepo,
      "DELETE FROM #{quote!(schema)}.bilimbi_migration_provenance WHERE version = $1",
      [@version]
    )
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
