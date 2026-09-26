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
        write_host_route_manifest(workspace_root)

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

  defp refresh_marker(module_root) do
    fingerprint =
      Bilimbi.Base.ModuleRegistry.MixDiscovery.workspace_fingerprint(module_root)

    compile_path = Mix.Project.compile_path()
    marker = Path.join(compile_path, @marker_prefix <> fingerprint)

    # Markers are dotfiles, which Path.wildcard/2 skips without match_dot. A
    # marker left behind lets a returning fingerprint (edit then revert, or
    # unmount then remount) rewrite its old file in place: the ebin mtime does
    # not move, so compile.app keeps the previous graph's .app metadata.
    existing_markers =
      Path.wildcard(Path.join(compile_path, @marker_prefix <> "*"), match_dot: true)

    if existing_markers == [marker] do
      {:noop, []}
    else
      File.mkdir_p!(compile_path)
      Enum.each(existing_markers, &File.rm!/1)
      File.write!(marker, fingerprint)
      {:ok, []}
    end
  end
end
