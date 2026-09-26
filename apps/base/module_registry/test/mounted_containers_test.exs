defmodule Bilimbi.Base.ModuleRegistry.MountedContainersTest do
  # Optional Domain and Extension repositories mount as nested Git
  # repositories under apps/domains/ and apps/extensions/. Each test builds a
  # throwaway workspace with its own repositories; nothing is mounted in the
  # real checkout.
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-mounted-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "apps/web"))
    File.write!(Path.join(root, "mix.exs"), "[]\n")
    on_exit(fn -> File.rm_rf!(root) end)

    put_container!(root, "apps/base", "base", :base)
    put_container!(root, "apps/core", "core", :core)
    put_module!(root, "apps/base", "base", "database")
    put_module!(root, "apps/core", "core", "company", dependencies: ["base/database"])

    %{root: root, web: Path.join(root, "apps/web")}
  end

  describe "with no mounted repository" do
    test "an absent mount root discovers only the Platform", %{root: root, web: web} do
      assert ids(root) == ["base/database", "core/company"]
      assert MixDiscovery.optional_container_dependencies(web) == []
    end

    test "a mount root holding only its guide discovers only the Platform", %{
      root: root,
      web: web
    } do
      for mount_root <- ["domains", "extensions"] do
        File.mkdir_p!(Path.join([root, "apps", mount_root]))
        File.write!(Path.join([root, "apps", mount_root, "AGENTS.md"]), "# guide\n")
      end

      assert ids(root) == ["base/database", "core/company"]
      assert MixDiscovery.optional_container_dependencies(web) == []
    end
  end

  describe "two mounted repositories" do
    setup %{root: root} do
      mount!(root, "domains", "people", :domain)

      put_module!(root, "apps/domains/people", "people", "employee",
        dependencies: ["core/company"]
      )

      mount!(root, "extensions", "acme", :extension)

      put_module!(root, "apps/extensions/acme", "acme", "payroll_export",
        dependencies: ["people/employee"]
      )

      :ok
    end

    test "are discovered, ordered, and bridged into the host without a central list", %{
      root: root,
      web: web
    } do
      assert ids(root) == [
               "base/database",
               "core/company",
               "people/employee",
               "acme/payroll_export"
             ]

      assert MixDiscovery.optional_container_dependencies(web) == [
               {:people, path: "../domains/people"},
               {:acme, path: "../extensions/acme"}
             ]

      people = Path.join(root, "apps/domains/people")

      assert MixDiscovery.container_dependencies(people) == [
               {:test_people_employee, path: "employee"}
             ]

      assert [bilimbi_module: descriptor] =
               MixDiscovery.application_env(Path.join(people, "employee"))

      assert descriptor.graph_module_ids == ids(root)
    end

    test "change the graph fingerprint when mounted or removed", %{root: root} do
      mounted = MixDiscovery.workspace_fingerprint(root)

      File.rm_rf!(Path.join(root, "apps/extensions/acme"))
      unmounted = MixDiscovery.workspace_fingerprint(root)

      refute unmounted == mounted
      assert ids(root) == ["base/database", "core/company", "people/employee"]

      File.write!(
        Path.join(root, "apps/domains/people/employee/bilimbi.module.exs"),
        File.read!(Path.join(root, "apps/domains/people/employee/bilimbi.module.exs")) <>
          "# edited\n"
      )

      refute MixDiscovery.workspace_fingerprint(root) == unmounted
    end

    test "may declare same-layer edges across repositories", %{root: root} do
      mount!(root, "domains", "stock", :domain)

      put_module!(root, "apps/domains/stock", "stock", "ledger",
        dependencies: ["people/employee"]
      )

      mount!(root, "extensions", "bridge", :extension)

      put_module!(root, "apps/extensions/bridge", "bridge", "sync",
        dependencies: ["acme/payroll_export", "stock/ledger"]
      )

      assert ids(root) == [
               "base/database",
               "core/company",
               "people/employee",
               "stock/ledger",
               "acme/payroll_export",
               "bridge/sync"
             ]
    end

    test "reject a cycle across repositories, naming only the cycle", %{root: root} do
      mount!(root, "domains", "stock", :domain)

      put_module!(root, "apps/domains/stock", "stock", "ledger",
        dependencies: ["people/employee"]
      )

      put_module!(root, "apps/domains/people", "people", "employee",
        dependencies: ["core/company", "stock/ledger"]
      )

      error = assert_raise ArgumentError, fn -> MixDiscovery.discover_workspace!(root) end

      assert error.message ==
               "module dependency cycle detected: people/employee, stock/ledger"
    end

    test "reject a dependency on a repository that is not mounted", %{root: root, web: web} do
      put_module!(root, "apps/extensions/acme", "acme", "payroll_export",
        dependencies: ["people/employee", "ledger/journal"]
      )

      assert_raise ArgumentError,
                   ~r/module acme\/payroll_export declares missing dependency ledger\/journal/,
                   fn -> MixDiscovery.discover_workspace!(root) end

      assert_raise ArgumentError, ~r/declares missing dependency ledger\/journal/, fn ->
        MixDiscovery.optional_container_dependencies(web)
      end
    end

    test "reject a dependency left behind when its repository is removed", %{root: root} do
      File.rm_rf!(Path.join(root, "apps/domains/people"))

      assert_raise ArgumentError,
                   ~r/module acme\/payroll_export declares missing dependency people\/employee/,
                   fn -> MixDiscovery.discover_workspace!(root) end
    end

    test "reject upward edges", %{root: root} do
      put_module!(root, "apps/domains/people", "people", "employee",
        dependencies: ["acme/payroll_export"]
      )

      assert_raise ArgumentError,
                   ~r/people\/employee in domain cannot depend on acme\/payroll_export in extension/,
                   fn -> MixDiscovery.discover_workspace!(root) end
    end
  end

  describe "mount validation" do
    test "rejects a container mounted under the other layer's root", %{root: root} do
      mount!(root, "extensions", "people", :domain)

      assert_raise ArgumentError,
                   ~r/container people .* declares layer :domain; this root accepts :extension/,
                   fn ->
                     MixDiscovery.discover_workspace!(root)
                   end
    end

    test "rejects a Domain or Extension container placed directly under apps/", %{root: root} do
      put_container!(root, "apps/people", "people", :domain)

      assert_raise ArgumentError, ~r/a Domain mounts under apps\/domains/, fn ->
        MixDiscovery.discover_workspace!(root)
      end
    end

    test "rejects a directory whose name is not its container ID", %{root: root} do
      put_container!(root, "apps/domains/staff", "people", :domain)

      assert_raise ArgumentError, ~r/must be mounted in a directory named people/, fn ->
        MixDiscovery.discover_workspace!(root)
      end
    end

    test "rejects a directory name that cannot be an OTP application", %{root: root} do
      put_container!(root, "apps/domains/Payroll-Export", "people", :domain)

      assert_raise ArgumentError, ~r/is not a valid container ID/, fn ->
        MixDiscovery.discover_workspace!(root)
      end
    end

    test "rejects a Platform container ID", %{root: root} do
      mount!(root, "domains", "web", :domain)

      assert_raise ArgumentError, ~r/container ID web .* is reserved for the Platform/, fn ->
        MixDiscovery.discover_workspace!(root)
      end
    end

    test "rejects a mounted directory without a container descriptor", %{root: root} do
      File.mkdir_p!(Path.join(root, "apps/domains/people"))

      assert_raise ArgumentError,
                   ~r/mounted container .*people is missing bilimbi.container.exs/,
                   fn ->
                     MixDiscovery.discover_workspace!(root)
                   end
    end

    test "rejects the same container ID in both mount roots", %{root: root} do
      mount!(root, "domains", "people", :domain)
      mount!(root, "extensions", "people", :extension)

      assert_raise ArgumentError, ~r/duplicate container ID: people/, fn ->
        MixDiscovery.discover_workspace!(root)
      end
    end

    test "rejects a container reached through a link", %{root: root} do
      outside = Path.join(root, "outside/people")
      put_container!(root, "outside/people", "people", :domain)
      File.mkdir_p!(Path.join(root, "apps/domains"))
      File.ln_s!(outside, Path.join(root, "apps/domains/people"))

      assert_raise ArgumentError, ~r/must be a directory inside the workspace, not a link/, fn ->
        MixDiscovery.discover_workspace!(root)
      end
    end
  end

  defp ids(root), do: root |> MixDiscovery.discover_workspace!() |> Enum.map(& &1.id)

  # A mounted container is its own Git repository; its .git directory must not
  # read as a module.
  defp mount!(root, mount_root, id, layer) do
    relative = Path.join(["apps", mount_root, id])
    put_container!(root, relative, id, layer)
    {_output, 0} = System.cmd("git", ["init", "--quiet", Path.join(root, relative)])
  end

  defp put_container!(root, relative, id, layer) do
    path = Path.join(root, relative)
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "bilimbi.container.exs"),
      inspect(id: id, kind: :container, layer: layer) <> "\n"
    )
  end

  defp put_module!(root, container_relative, container_id, name, overrides \\ []) do
    path = Path.join([root, container_relative, name])
    File.mkdir_p!(path)

    {container, _binding} =
      Code.eval_file(Path.join([root, container_relative, "bilimbi.container.exs"]))

    layer = Keyword.fetch!(container, :layer)

    descriptor = [
      id: "#{container_id}/#{name}",
      kind: :module,
      layer: layer,
      required: layer in [:base, :core],
      otp_app: String.to_atom("test_#{container_id}_#{name}"),
      namespace: Module.concat([Test, Macro.camelize(container_id), Macro.camelize(name)]),
      dependencies: Keyword.get(overrides, :dependencies, []),
      migrations: nil,
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil
    ]

    File.write!(
      Path.join(path, "bilimbi.module.exs"),
      inspect(descriptor, pretty: true, limit: :infinity) <> "\n"
    )
  end
end
