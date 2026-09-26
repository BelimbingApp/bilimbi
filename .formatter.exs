[discovery_file] = Path.wildcard("apps/base/*/mix/module_discovery.exs")
Code.require_file(discovery_file)

modules = Bilimbi.Base.ModuleRegistry.MixDiscovery.discover_workspace!(File.cwd!())

subdirectories =
  modules
  |> Enum.flat_map(&[&1.container_path, &1.path])
  |> Enum.map(&Path.relative_to(&1, File.cwd!()))
  |> Enum.uniq()
  |> Kernel.++(["apps/web"])

[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["mix.exs", "mix/*.exs", "config/*.exs"],
  subdirectories: subdirectories
]
