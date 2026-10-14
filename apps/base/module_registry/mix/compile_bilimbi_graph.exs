defmodule Mix.Tasks.Compile.BilimbiGraph do
  @moduledoc false

  use Mix.Task.Compiler

  @recursive true
  @marker_prefix ".bilimbi_graph_"

  @impl true
  def run(_arguments) do
    config = Mix.Project.config()

    case {config[:bilimbi_module_root], config[:bilimbi_workspace_root]} do
      {module_root, _} when is_binary(module_root) ->
        workspace_root =
          Bilimbi.Base.ModuleRegistry.MixDiscovery.workspace_root!(module_root)

        Bilimbi.Base.ModuleRegistry.MixDiscovery.write_route_manifest!(workspace_root)
        refresh_marker(module_root)

      {nil, workspace_root} when is_binary(workspace_root) ->
        route_result = write_host_route_manifest(workspace_root)

        # A mounted container can change the host's OTP application list
        # without contributing any routes. Refresh its .app on graph changes
        # too, so unmounting does not leave a missing application at startup.
        graph_result = refresh_marker(workspace_root)

        case {route_result, graph_result} do
          {{:noop, []}, {:noop, []}} -> {:noop, []}
          _changed -> {:ok, []}
        end

      _other ->
        {:noop, []}
    end
  end

  defp write_host_route_manifest(workspace_root) do
    manifest =
      Bilimbi.Base.ModuleRegistry.MixDiscovery.route_manifest_path(workspace_root)

    previous = if File.regular?(manifest), do: File.read!(manifest)

    Bilimbi.Base.ModuleRegistry.MixDiscovery.write_route_manifest!(workspace_root)

    current = File.read!(manifest)

    if previous == current do
      {:noop, []}
    else
      {:ok, []}
    end
  end

  defp refresh_marker(project_root) do
    fingerprint =
      Bilimbi.Base.ModuleRegistry.MixDiscovery.workspace_fingerprint(project_root)

    compile_path = Mix.Project.compile_path()
    marker = Path.join(compile_path, @marker_prefix <> fingerprint)

    # Keep only the current marker, including dotfiles. Mix's compile.app
    # compares whole-second mtimes: even replacing a marker can leave ebin
    # and the .app in the same tick. Invalidate the generated .app explicitly
    # on a fingerprint change so metadata never depends on clock resolution.
    existing_markers =
      Path.wildcard(Path.join(compile_path, @marker_prefix <> "*"), match_dot: true)

    if existing_markers == [marker] do
      {:noop, []}
    else
      File.mkdir_p!(compile_path)
      Enum.each(existing_markers, &File.rm!/1)
      app_file = Path.join(compile_path, "#{Mix.Project.config()[:app]}.app")
      if File.regular?(app_file), do: File.rm!(app_file)
      File.write!(marker, fingerprint)
      {:ok, []}
    end
  end
end

