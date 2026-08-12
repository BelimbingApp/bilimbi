defmodule Mix.Tasks.Compile.BilimbiGraph do
  @moduledoc false

  use Mix.Task.Compiler

  @recursive true
  @marker_prefix ".bilimbi_graph_"

  @impl true
  def run(_arguments) do
    case Mix.Project.config()[:bilimbi_module_root] do
      nil ->
        {:noop, []}

      module_root ->
        refresh_marker(module_root)
    end
  end

  defp refresh_marker(module_root) do
    fingerprint =
      Bilimbi.Base.ModuleRegistry.MixDiscovery.workspace_fingerprint(module_root)

    compile_path = Mix.Project.compile_path()
    marker = Path.join(compile_path, @marker_prefix <> fingerprint)
    existing_markers = Path.wildcard(Path.join(compile_path, @marker_prefix <> "*"))

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
