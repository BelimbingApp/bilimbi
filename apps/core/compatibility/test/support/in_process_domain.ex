defmodule Bilimbi.Core.Compatibility.InProcessDomain do
  @moduledoc """
  Mounts a throwaway Domain in this VM the way a host build loads a cloned
  one: a checkout under a temporary directory, a build directory whose `priv`
  is the checkout's, and a loaded application whose environment carries the
  descriptor. Nothing is mounted in the real checkout, so `Compatibility`
  reads the Domain exactly as it reads any installed module while the package
  test runs in-process against `MigrationTestRepo`.

  `mount!/2` takes the migrations the Domain ships as
  `{version, disposition, name, body}`, where `body` is the migration
  module's content after `use Ecto.Migration` (`create_table/2` and
  `failing/1` build the two shapes the tests need), and an optional
  `contract:` map of `tables` and `contributions` that the Domain's
  `SchemaContract` serves. A caller that remounts a different file under the
  same version passes a different `name`, so the module is not redefined.

  `MountedDomainFixture` is the counterpart for nested `mix` runs from the
  umbrella root; this fixture never leaves the test VM.
  """

  alias Bilimbi.Base.ModuleRegistry

  @id "proof_factory/widget"
  @otp_app :bilimbi_proof_factory_widget
  @namespace Bilimbi.ProofFactory.Widget

  def id, do: @id
  def otp_app, do: @otp_app

  @doc "A migration body that creates each table with one non-null string column."
  def create_tables(tables, column \\ :label) do
    creates =
      Enum.map_join(tables, "\n", fn table ->
        """
            create table(:#{table}) do
              add :#{column}, :string, null: false
            end
        """
      end)

    "  def change do\n#{creates}  end\n"
  end

  @doc "A migration body that creates `table` with one non-null string column."
  def create_table(table, column \\ :label), do: create_tables([table], column)

  @doc "A migration body whose `up` raises, so a run stops after what preceded it."
  def failing(message) do
    """
      def up, do: raise(#{inspect(message)})
      def down, do: :ok
    """
  end

  @doc "The contract table spec for a table `create_table/2` created."
  def table_spec(table, column \\ "label") do
    %{
      name: table,
      columns: %{
        "id" => %{type: :bigint, nullable: false, default: {:sequence, "#{table}_id_seq"}},
        column => %{type: {:varchar, 255}, nullable: false, default: nil}
      },
      indexes: %{"#{table}_pkey" => %{columns: ["id"], unique: true, where: nil}},
      foreign_keys: %{}
    }
  end

  @doc """
  Mounts the Domain. The context carries the temporary `root` and a `suffix`
  that keeps migration module names unique across tests in one VM.
  """
  def mount!(%{root: root, suffix: suffix}, opts) do
    migrations = Keyword.fetch!(opts, :migrations)
    contract = Keyword.get(opts, :contract)
    checkout = Path.join(root, "apps/domains/proof_factory")
    module_root = Path.join(checkout, "widget")
    migrations_dir = Path.join(module_root, "priv/repo/migrations")
    File.mkdir_p!(migrations_dir)

    for {version, _disposition, name, body} <- migrations do
      File.write!(
        Path.join(migrations_dir, "#{version}_#{Macro.underscore(name)}.exs"),
        """
        defmodule #{inspect(@namespace)}.Migrations.#{name}#{suffix} do
          use Ecto.Migration

        #{body}
        end
        """
      )
    end

    {_output, 0} = System.cmd("git", ["init", "--quiet", checkout])

    build = Path.join(root, "_build/lib/#{@otp_app}")
    File.mkdir_p!(Path.join(build, "ebin"))
    File.ln_s!(Path.join(module_root, "priv"), Path.join(build, "priv"))
    true = Code.prepend_path(Path.join(build, "ebin"))

    installed = ModuleRegistry.installed_modules!()
    [%{graph_fingerprint: fingerprint} | _rest] = installed

    descriptor = %{
      id: Keyword.get(opts, :id, @id),
      kind: :module,
      layer: :domain,
      required: false,
      otp_app: @otp_app,
      namespace: @namespace,
      dependencies: ["base/database"],
      migrations: "priv/repo/migrations",
      migration_dispositions:
        Map.new(migrations, fn {version, disposition, _name, _body} -> {version, disposition} end),
      web: nil,
      schema_contract: if(contract, do: Bilimbi.ProofFactory.Widget.SchemaContract),
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
           env: [bilimbi_module: descriptor, schema_contract: contract]
         ]}
      )
  end

  @doc """
  Unmounts the Domain: unloads its application and removes the checkout and
  build output, as a clean rebuild without the repository would. The database
  is never touched.
  """
  def unmount!(root) do
    _ = Application.unload(@otp_app)
    build = Path.join(root, "_build/lib/#{@otp_app}")
    Code.delete_path(Path.join(build, "ebin"))
    File.rm_rf!(build)
    File.rm_rf!(Path.join(root, "apps/domains/proof_factory"))
  end
end
