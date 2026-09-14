defmodule Mix.Tasks.Bilimbi.ServerTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  test "reports missing application metadata as stale" do
    workspace_root = MixDiscovery.workspace_root!(__DIR__)

    build_path =
      Path.join(System.tmp_dir!(), "bilimbi-server-test-#{System.unique_integer([:positive])}")

    try do
      assert {:stale, issues} =
               Mix.Tasks.Bilimbi.Server.graph_status(
                 workspace_root: workspace_root,
                 build_path: build_path
               )

      assert Enum.any?(issues, fn
               {_module, :missing_application_metadata} -> true
               _ -> false
             end)
    after
      File.rm_rf!(build_path)
    end
  end

  test "reports fingerprint and order metadata drift as stale" do
    workspace_root = MixDiscovery.workspace_root!(__DIR__)
    build_path = copy_compiled_app_files(workspace_root)

    try do
      [module | _] = MixDiscovery.discover_workspace!(workspace_root)
      module_id = module.id
      app_file = application_file(build_path, module)
      update_descriptor(app_file, graph_fingerprint: "stale", order: -1)

      assert {:stale, issues} =
               Mix.Tasks.Bilimbi.Server.graph_status(
                 workspace_root: workspace_root,
                 build_path: build_path
               )

      assert {^module_id, {:fingerprint, "stale", _expected}} =
               Enum.find(issues, fn
                 {^module_id, {:fingerprint, _, _}} -> true
                 _issue -> false
               end)

      assert {^module_id, {:order, -1, 0}} =
               Enum.find(issues, fn
                 {^module_id, {:order, _, 0}} -> true
                 _issue -> false
               end)
    after
      File.rm_rf!(build_path)
    end
  end

  test "reenables compilation after cleaning dependency builds" do
    Mix.Task.Compiler.reenable()

    assert {:ok, _warnings} = Mix.Task.run("compile")
  end

  defp copy_compiled_app_files(workspace_root) do
    build_path =
      Path.join(System.tmp_dir!(), "bilimbi-server-test-#{System.unique_integer([:positive])}")

    expected_fingerprint = MixDiscovery.workspace_fingerprint(workspace_root)

    Enum.each(Enum.with_index(MixDiscovery.discover_workspace!(workspace_root)), fn {module,
                                                                                     order} ->
      target = application_file(build_path, module)
      File.mkdir_p!(Path.dirname(target))

      descriptor = [graph_fingerprint: expected_fingerprint, order: order]
      application = {:application, module.otp_app, [env: [bilimbi_module: descriptor]]}
      File.write!(target, IO.iodata_to_binary(:io_lib.format("~p.~n", [application])))
    end)

    build_path
  end

  defp application_file(build_path, module) do
    Path.join([
      build_path,
      "lib",
      Atom.to_string(module.otp_app),
      "ebin",
      Atom.to_string(module.otp_app) <> ".app"
    ])
  end

  defp update_descriptor(app_file, updates) do
    {:ok, [{:application, app, properties}]} = :file.consult(String.to_charlist(app_file))
    {:ok, environment} = Keyword.fetch(properties, :env)
    {:ok, descriptor} = Keyword.fetch(environment, :bilimbi_module)

    descriptor =
      Enum.reduce(updates, descriptor, fn {key, value}, acc -> Keyword.put(acc, key, value) end)

    environment = Keyword.put(environment, :bilimbi_module, descriptor)
    properties = Keyword.put(properties, :env, environment)

    File.write!(
      app_file,
      IO.iodata_to_binary(:io_lib.format("~p.~n", [{:application, app, properties}]))
    )
  end
end
