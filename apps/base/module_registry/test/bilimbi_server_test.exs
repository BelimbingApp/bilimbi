defmodule Mix.Tasks.Bilimbi.ServerTest do
  use ExUnit.Case, async: true

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
end
