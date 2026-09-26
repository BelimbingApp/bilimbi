defmodule Bilimbi.Core.Compatibility.MountedDomainFixture do
  @moduledoc """
  Mounts a throwaway Domain in the real checkout, so a nested `mix` run from the umbrella root compiles and loads it
  as it would a cloned Domain repository.

  Like Factory, the Domain ships a compatible baseline its schema contract
  requires, numbered after every Platform Bilimbi-only migration, and a
  Bilimbi-only migration after that.

  Git ignores everything below `apps/domains/`, so the fixture never reaches a
  commit. A marker file tells a stale fixture from a real mounted repository:
  `mount!/0` removes a fixture a killed run left behind and refuses to touch a
  directory without the marker.
  """

  @container "e2e_fixture"
  @otp_app :bilimbi_e2e_fixture_ledger
  @baseline_version 20_991_231_000_000
  @version 20_991_231_000_001
  @marker ".bilimbi-e2e-fixture"
  @workspace_root Path.expand("../../../../..", __DIR__)

  def baseline_version, do: @baseline_version
  def baseline_table, do: "e2e_fixture_ledger_entries"
  def version, do: @version
  def table, do: "e2e_fixture_ledger_rows"

  def mount! do
    unmount!()

    root = container_root()
    module_root = Path.join(root, "ledger")
    migrations = Path.join(module_root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    File.mkdir_p!(Path.join(module_root, "lib"))
    File.write!(Path.join(root, @marker), "")

    File.write!(
      Path.join(root, "bilimbi.container.exs"),
      inspect(id: @container, kind: :container, layer: :domain) <> "\n"
    )

    File.write!(Path.join(root, "mix.exs"), container_mix())

    File.write!(
      Path.join(module_root, "bilimbi.module.exs"),
      inspect(descriptor(), pretty: true, limit: :infinity) <> "\n"
    )

    File.write!(Path.join(module_root, "mix.exs"), module_mix())

    File.write!(
      Path.join(module_root, "lib/ledger.ex"),
      "defmodule Bilimbi.E2eFixture.Ledger do\nend\n"
    )

    File.write!(Path.join(module_root, "lib/schema_contract.ex"), schema_contract())

    File.write!(
      Path.join(migrations, "#{@baseline_version}_create_e2e_fixture_ledger_entries.exs"),
      """
      defmodule Bilimbi.E2eFixture.Ledger.Migrations.CreateEntries do
        use Ecto.Migration

        def change do
          create table(:#{baseline_table()}) do
            add :label, :string, null: false
          end
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "#{@version}_create_e2e_fixture_ledger_rows.exs"),
      """
      defmodule Bilimbi.E2eFixture.Ledger.Migrations.CreateRows do
        use Ecto.Migration

        def change do
          create table(:#{table()}) do
            add :label, :string, null: false
          end
        end
      end
      """
    )

    :ok
  end

  # Removes the checkout and its build output. The next nested compile
  # rewrites every module's graph metadata back to the unmounted workspace.
  def unmount! do
    root = container_root()

    if File.exists?(root) do
      unless File.regular?(Path.join(root, @marker)) do
        raise "#{root} is a mounted repository, not the end-to-end fixture; unmount it first"
      end

      File.rm_rf!(root)
    end

    for build <- Path.wildcard(Path.join(@workspace_root, "_build/*/lib")),
        app <- [@container, Atom.to_string(@otp_app)] do
      File.rm_rf!(Path.join(build, app))
    end

    :ok
  end

  defp container_root, do: Path.join(@workspace_root, "apps/domains/#{@container}")

  defp descriptor do
    [
      id: "#{@container}/ledger",
      kind: :module,
      layer: :domain,
      required: false,
      otp_app: @otp_app,
      namespace: Bilimbi.E2eFixture.Ledger,
      dependencies: ["base/database"],
      migrations: "priv/repo/migrations",
      migration_dispositions: %{
        @baseline_version => :compatible_baseline,
        @version => :bilimbi_only
      },
      web: nil,
      schema_contract: Bilimbi.E2eFixture.Ledger.SchemaContract,
      contribution_provider: nil,
      dev_seed: nil
    ]
  end

  defp schema_contract do
    """
    defmodule Bilimbi.E2eFixture.Ledger.SchemaContract do
      @behaviour Bilimbi.Base.Database.SchemaContract

      @impl true
      def tables do
        [
          %{
            name: "#{baseline_table()}",
            columns: %{
              "id" => %{
                type: :bigint,
                nullable: false,
                default: {:sequence, "#{baseline_table()}_id_seq"}
              },
              "label" => %{type: {:varchar, 255}, nullable: false, default: nil}
            },
            indexes: %{
              "#{baseline_table()}_pkey" => %{columns: ["id"], unique: true, where: nil}
            },
            foreign_keys: %{}
          }
        ]
      end
    end
    """
  end

  defp container_mix do
    """
    [discovery_file] =
      Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

    Code.require_file(discovery_file)
    Code.require_file(Path.expand("../../../mix/composition_lock.exs", __DIR__))

    defmodule Bilimbi.E2eFixture.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{@container},
          version: "0.1.0",
          build_path: "../../../_build",
          config_path: "../../../config/config.exs",
          deps_path: "../../../deps",
          lockfile: Bilimbi.CompositionLock.lockfile!(Path.expand("../../..", __DIR__)),
          elixir: "~> 1.20",
          deps: Bilimbi.Base.ModuleRegistry.MixDiscovery.container_dependencies(__DIR__)
        ]
      end
    end
    """
  end

  defp module_mix do
    """
    Code.require_file(Path.expand("../../../../mix/composition_lock.exs", __DIR__))

    [discovery_file] =
      Path.wildcard(Path.expand("../../../../apps/base/*/mix/module_discovery.exs", __DIR__))

    Code.require_file(discovery_file)

    defmodule Bilimbi.E2eFixture.Ledger.MixProject do
      use Mix.Project

      @workspace_root Path.expand("../../../..", __DIR__)

      def project do
        [
          app: :#{@otp_app},
          version: "0.1.0",
          build_path: Path.join(@workspace_root, "_build"),
          config_path: Path.join(@workspace_root, "config/config.exs"),
          deps_path: Path.join(@workspace_root, "deps"),
          lockfile: Bilimbi.CompositionLock.lockfile!(@workspace_root),
          elixir: "~> 1.20",
          compilers: [:bilimbi_graph] ++ Mix.compilers(),
          bilimbi_module_root: __DIR__,
          deps: Bilimbi.Base.ModuleRegistry.MixDiscovery.module_dependencies(__DIR__)
        ]
      end

      def application do
        [
          extra_applications: [:logger],
          env: Bilimbi.Base.ModuleRegistry.MixDiscovery.application_env(__DIR__)
        ]
      end
    end
    """
  end
end
