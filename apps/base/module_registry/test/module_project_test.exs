defmodule Bilimbi.Base.ModuleRegistry.ModuleProjectTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @module_root Path.expand("..", __DIR__)
  @workspace_root Path.expand("../../../..", __DIR__)

  test "module_project/2 returns the workspace-shared project shape" do
    project = MixDiscovery.module_project(@module_root, app: :probe, deps: [{:jason, "~> 1.4"}])

    assert project[:app] == :probe
    assert project[:build_path] == Path.join(@workspace_root, "_build")
    assert project[:config_path] == Path.join(@workspace_root, "config/config.exs")
    assert project[:deps_path] == Path.join(@workspace_root, "deps")
    assert project[:lockfile] == Bilimbi.CompositionLock.lockfile!(@workspace_root)
    assert project[:bilimbi_module_root] == @module_root
    assert project[:aliases] == []
    assert hd(project[:compilers]) == :bilimbi_graph
    assert {:jason, "~> 1.4"} in project[:deps]
  end

  test "elixirc_paths adds test/support only when the module has that directory" do
    assert File.dir?(Path.join(@module_root, "test/support"))

    assert MixDiscovery.module_project(@module_root, app: :probe)[:elixirc_paths] == [
             "lib",
             "test/support"
           ]

    bare_root =
      @workspace_root
      |> MixDiscovery.discover_workspace!()
      |> Enum.map(& &1.path)
      |> Enum.find(&(not File.dir?(Path.join(&1, "test/support"))))

    assert bare_root, "no installed module lacks test/support, so this branch is untested"
    assert MixDiscovery.module_project(bare_root, app: :probe)[:elixirc_paths] == ["lib"]
  end

  test "module_project/2 rejects an unknown option and a missing app" do
    assert_raise ArgumentError, fn ->
      MixDiscovery.module_project(@module_root, app: :probe, dep: [])
    end

    assert_raise KeyError, fn -> MixDiscovery.module_project(@module_root, []) end
  end

  test "module_application/2 defaults to :logger and appends caller env to the descriptor env" do
    application = MixDiscovery.module_application(@module_root, env: [probe_key: :value])

    assert application[:extra_applications] == [:logger]
    refute Keyword.has_key?(application, :mod)

    assert [{:bilimbi_module, %{id: "base/module_registry"}}, {:probe_key, :value}] =
             application[:env]
  end

  test "module_application/2 keeps a given :mod and drops a nil one" do
    assert MixDiscovery.module_application(@module_root, mod: {Probe.Application, []})[:mod] ==
             {Probe.Application, []}

    refute Keyword.has_key?(MixDiscovery.module_application(@module_root, mod: nil), :mod)
  end
end
