defmodule Bilimbi.Base.ModuleRegistry.MixDiscoveryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-discovery-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "apps"))
    File.write!(Path.join(root, "mix.exs"), "[]\n")
    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root}
  end

  test "discovers Base, Core, Domain, and Extension containers with deterministic order", %{
    root: root
  } do
    put_container!(root, "base", :base)
    put_container!(root, "core", :core)
    put_container!(root, "people", :domain)
    put_container!(root, "acme", :extension)

    put_module!(root, "base", "database")
    put_module!(root, "base", "tenancy", dependencies: ["base/database"])
    put_module!(root, "core", "company", dependencies: ["base/tenancy"])
    put_module!(root, "people", "employee", dependencies: ["core/company"])
    put_module!(root, "acme", "payroll_export", dependencies: ["people/employee"])

    assert Enum.map(MixDiscovery.discover_workspace!(root), & &1.id) == [
             "base/database",
             "base/tenancy",
             "core/company",
             "people/employee",
             "acme/payroll_export"
           ]
  end

  test "dependency order wins before stable ID tie-breaking", %{root: root} do
    put_container!(root, "base", :base)
    put_module!(root, "base", "mid")
    put_module!(root, "base", "zzz")
    put_module!(root, "base", "aaa", dependencies: ["base/zzz"])

    assert Enum.map(MixDiscovery.discover_workspace!(root), & &1.id) == [
             "base/mid",
             "base/zzz",
             "base/aaa"
           ]
  end

  test "container dependencies and tests are generated from immediate module directories", %{
    root: root
  } do
    base = put_container!(root, "base", :base)
    put_module!(root, "base", "zeta")
    put_module!(root, "base", "alpha")

    assert MixDiscovery.container_dependencies(base) == [
             {:test_base_alpha, [path: "alpha"]},
             {:test_base_zeta, [path: "zeta"]}
           ]

    assert MixDiscovery.container_test_commands(base) == [
             ~s(cmd --cd "alpha" mix test),
             ~s(cmd --cd "zeta" mix test)
           ]
  end

  test "application metadata carries the Mix-approved resolved order", %{root: root} do
    put_container!(root, "base", :base)
    first = put_module!(root, "base", "first")
    second = put_module!(root, "base", "second", dependencies: ["base/first"])

    assert [bilimbi_module: %{id: "base/first", order: 0, graph_fingerprint: fingerprint}] =
             MixDiscovery.application_env(first)

    assert [bilimbi_module: %{id: "base/second", order: 1, graph_fingerprint: ^fingerprint}] =
             MixDiscovery.application_env(second)
  end

  test "workspace fingerprint changes when source composition changes", %{root: root} do
    put_container!(root, "base", :base)
    put_module!(root, "base", "first")
    first_fingerprint = MixDiscovery.workspace_fingerprint(root)

    put_module!(root, "base", "second", dependencies: ["base/first"])

    refute MixDiscovery.workspace_fingerprint(root) == first_fingerprint
  end

  test "validates and publishes the descriptor-owned contribution provider", %{root: root} do
    put_container!(root, "base", :base)

    module_root =
      put_module!(root, "base", "settings",
        contribution_provider: Test.Base.Settings.Contributions
      )

    assert [
             bilimbi_module: %{
               contribution_provider: Test.Base.Settings.Contributions
             }
           ] = MixDiscovery.application_env(module_root)

    File.rm_rf!(module_root)
    put_module!(root, "base", "settings", contribution_provider: "not-a-module")

    assert_raise ArgumentError,
                 ~r/contribution_provider must be nil or a non-nil module atom/,
                 fn ->
                   MixDiscovery.discover_workspace!(root)
                 end
  end

  test "rejects missing and malformed descriptors", %{root: root} do
    base = put_container!(root, "base", :base)
    File.mkdir_p!(Path.join(base, "missing"))

    assert_raise ArgumentError, ~r/is missing bilimbi\.module\.exs/, fn ->
      MixDiscovery.discover_workspace!(root)
    end

    File.write!(Path.join([base, "missing", "bilimbi.module.exs"]), ":not_a_descriptor\n")

    assert_raise ArgumentError, ~r/descriptor must return a keyword list/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  test "container composition rejects a missing container descriptor", %{root: root} do
    base = Path.join([root, "apps", "base"])
    File.mkdir_p!(base)

    assert_raise ArgumentError, ~r/is missing bilimbi\.container\.exs/, fn ->
      MixDiscovery.container_dependencies(base)
    end
  end

  test "rejects duplicate stable and OTP application IDs", %{root: root} do
    put_container!(root, "base", :base)
    put_container!(root, "core", :core)
    put_module!(root, "base", "one", id: "shared/module")
    put_module!(root, "core", "two", id: "shared/module")

    assert_raise ArgumentError, ~r/duplicate stable module ID/, fn ->
      MixDiscovery.discover_workspace!(root)
    end

    File.rm_rf!(Path.join([root, "apps", "core"]))
    put_module!(root, "base", "two", otp_app: :test_base_one)

    assert_raise ArgumentError, ~r/duplicate OTP application ID/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  test "rejects missing dependencies and dependency cycles", %{root: root} do
    put_container!(root, "base", :base)
    put_module!(root, "base", "one", dependencies: ["base/missing"])

    assert_raise ArgumentError, ~r/declares missing dependency base\/missing/, fn ->
      MixDiscovery.discover_workspace!(root)
    end

    File.rm_rf!(Path.join([root, "apps", "base", "one"]))
    put_module!(root, "base", "one", dependencies: ["base/two"])
    put_module!(root, "base", "two", dependencies: ["base/one"])

    assert_raise ArgumentError, ~r/dependency cycle detected: base\/one, base\/two/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  test "rejects container-layer mismatch and upward dependencies", %{root: root} do
    put_container!(root, "base", :base)
    put_container!(root, "core", :core)
    put_module!(root, "base", "wrong", layer: :core)

    assert_raise ArgumentError, ~r/declares layer :core, but container base is :base/, fn ->
      MixDiscovery.discover_workspace!(root)
    end

    File.rm_rf!(Path.join([root, "apps", "base", "wrong"]))
    put_module!(root, "core", "company")
    put_module!(root, "base", "upward", dependencies: ["core/company"])

    assert_raise ArgumentError,
                 ~r/base\/upward in base cannot depend on core\/company in core/,
                 fn ->
                   MixDiscovery.discover_workspace!(root)
                 end
  end

  test "Compatibility-closure check names a contributor missing from the coordinator", %{
    root: root
  } do
    put_container!(root, "base", :base)
    put_container!(root, "core", :core)
    put_module!(root, "base", "database")

    put_module!(root, "core", "user",
      dependencies: ["base/database"],
      schema_contract: Test.Core.User.SchemaContract
    )

    put_module!(root, "core", "compatibility", dependencies: ["base/database"])

    modules = MixDiscovery.discover_workspace!(root)

    assert MixDiscovery.missing_compatibility_contributors(modules) == ["core/user"]

    assert MixDiscovery.missing_compatibility_contributors(modules, [
             "base/database",
             "core/user"
           ]) == []
  end

  test "Compatibility-closure check ignores modules that contribute neither migrations nor a contract",
       %{root: root} do
    put_container!(root, "base", :base)
    put_container!(root, "core", :core)
    put_module!(root, "base", "database")
    put_module!(root, "base", "module_registry")
    put_module!(root, "core", "compatibility", dependencies: ["base/database"])

    modules = MixDiscovery.discover_workspace!(root)
    assert MixDiscovery.missing_compatibility_contributors(modules) == []
  end

  test "rejects a descriptor missing the web key", %{root: root} do
    put_container!(root, "base", :base)
    path = Path.join([root, "apps", "base", "broken"])
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "bilimbi.module.exs"),
      inspect(
        [
          id: "base/broken",
          kind: :module,
          layer: :base,
          required: true,
          otp_app: :test_base_broken,
          namespace: Test.Base.Broken,
          dependencies: [],
          migrations: nil,
          schema_contract: nil,
          contribution_provider: nil
        ],
        pretty: true,
        limit: :infinity
      ) <> "\n"
    )

    assert_raise ArgumentError, ~r/expected keys/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  test "accepts web: pointing at an existing route data file", %{root: root} do
    put_container!(root, "base", :base)
    module_root = put_module!(root, "base", "ui", web: "priv/web_routes.exs")
    File.mkdir_p!(Path.join(module_root, "priv"))
    File.write!(Path.join(module_root, "priv/web_routes.exs"), "[]\n")

    assert [%{id: "base/ui", web: "priv/web_routes.exs"}] = MixDiscovery.discover_workspace!(root)
  end

  test "rejects web: pointing at a missing file", %{root: root} do
    put_container!(root, "base", :base)
    put_module!(root, "base", "ui", web: "priv/web_routes.exs")

    assert_raise ArgumentError, ~r/declared web route data file does not exist/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  test "rejects web: containing a parent directory segment", %{root: root} do
    put_container!(root, "base", :base)
    put_module!(root, "base", "ui", web: "../other/web_routes.exs")

    assert_raise ArgumentError, ~r/web must be nil or a safe relative path/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  test "route manifest includes a module live route with its source", %{root: root} do
    put_container!(root, "base", :base)
    module_root = put_module!(root, "base", "ui", web: "priv/web_routes.exs")
    File.mkdir_p!(Path.join(module_root, "priv"))

    File.write!(
      Path.join(module_root, "priv/web_routes.exs"),
      """
      [
        %{path: "/widgets", live: Test.WidgetLive, session: :auth, capability: nil}
      ]
      """
    )

    MixDiscovery.write_route_manifest!(root)
    {routes, _binding} = Code.eval_file(MixDiscovery.route_manifest_path(root))

    assert [
             %{
               path: "/widgets",
               live: Test.WidgetLive,
               session: :auth,
               capability: nil,
               source: "base/ui"
             }
           ] = routes
  end

  test "route manifest appends host routes with source web", %{root: root} do
    put_container!(root, "base", :base)
    module_root = put_module!(root, "base", "ui", web: "priv/web_routes.exs")
    File.mkdir_p!(Path.join(module_root, "priv"))
    File.write!(Path.join(module_root, "priv/web_routes.exs"), "[%{path: \"/widgets\"}]\n")

    File.mkdir_p!(Path.join([root, "apps", "web", "priv"]))

    File.write!(
      Path.join([root, "apps", "web", "priv", "web_routes.exs"]),
      "[%{path: \"/\", live: Test.LoginLive, session: :anonymous, capability: nil}]\n"
    )

    MixDiscovery.write_route_manifest!(root)
    {routes, _binding} = Code.eval_file(MixDiscovery.route_manifest_path(root))

    assert Enum.map(routes, &{&1.path, &1.source}) == [
             {"/widgets", "base/ui"},
             {"/", "web"}
           ]
  end

  test "workspace fingerprint changes when a web_routes.exs file changes", %{root: root} do
    put_container!(root, "base", :base)
    module_root = put_module!(root, "base", "ui", web: "priv/web_routes.exs")
    File.mkdir_p!(Path.join(module_root, "priv"))
    File.write!(Path.join(module_root, "priv/web_routes.exs"), "[]\n")
    first = MixDiscovery.workspace_fingerprint(root)

    File.write!(Path.join(module_root, "priv/web_routes.exs"), "[%{path: \"/x\"}]\n")
    refute MixDiscovery.workspace_fingerprint(root) == first
  end

  defp put_container!(root, id, layer) do
    path = Path.join([root, "apps", id])
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "bilimbi.container.exs"),
      inspect([id: id, kind: :container, layer: layer], pretty: true) <> "\n"
    )

    path
  end

  defp put_module!(root, container, name, overrides \\ []) do
    path = Path.join([root, "apps", container, name])
    File.mkdir_p!(Path.join(path, "test"))
    File.mkdir_p!(Path.join(path, "docs"))
    File.write!(Path.join(path, "mix.exs"), "[]\n")

    layer = Keyword.get(overrides, :layer, container_layer(root, container))

    descriptor = [
      id: Keyword.get(overrides, :id, "#{container}/#{name}"),
      kind: :module,
      layer: layer,
      required: layer in [:base, :core],
      otp_app: Keyword.get(overrides, :otp_app, String.to_atom("test_#{container}_#{name}")),
      namespace: Module.concat([Test, Macro.camelize(container), Macro.camelize(name)]),
      dependencies: Keyword.get(overrides, :dependencies, []),
      migrations: Keyword.get(overrides, :migrations, nil),
      web: Keyword.get(overrides, :web, nil),
      schema_contract: Keyword.get(overrides, :schema_contract, nil),
      contribution_provider: Keyword.get(overrides, :contribution_provider, nil)
    ]

    File.write!(
      Path.join(path, "bilimbi.module.exs"),
      inspect(descriptor, pretty: true, limit: :infinity) <> "\n"
    )

    path
  end

  defp container_layer(root, container) do
    {descriptor, _binding} =
      Code.eval_file(Path.join([root, "apps", container, "bilimbi.container.exs"]))

    Keyword.fetch!(descriptor, :layer)
  end
end
