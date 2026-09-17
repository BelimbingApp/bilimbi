defmodule BilimbiWeb.HeroiconsManifest do
  @moduledoc """
  The `hero-` names the Tailwind build can emit.

  Derived the way the Tailwind plugin derives them: the plugin's own icon
  directory and its per-directory suffix table are parsed out of
  `assets/vendor/heroicons.js`, then every SVG below each directory becomes one
  accepted `hero-` name. The accepted names therefore come from the package the
  build consumes; copying the four suffixes into a test would make that test a
  second list to maintain.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @plugin Path.expand("../../assets/vendor/heroicons.js", __DIR__)
  @workspace Path.expand("../../../..", __DIR__)

  @doc "Every `hero-` name the pinned Heroicons release lets Tailwind emit."
  @spec names() :: MapSet.t(String.t())
  def names do
    plugin = File.read!(@plugin)

    icons_dir = icons_dir(plugin)
    suffixes = suffixes(plugin)

    for [suffix, dir] <- suffixes,
        file <- svg_files(Path.join(icons_dir, dir)),
        into: MapSet.new() do
      "hero-" <> Path.basename(file, ".svg") <> suffix
    end
  end

  @doc "The Tailwind plugin this manifest is read from, for failure messages."
  @spec plugin_path() :: String.t()
  def plugin_path, do: Path.relative_to(@plugin, @workspace)

  defp icons_dir(plugin) do
    case Regex.run(~r/path\.join\(__dirname,\s*"([^"]+)"\)/, plugin, capture: :all_but_first) do
      [relative] ->
        Path.expand(relative, Path.dirname(@plugin))

      nil ->
        flunk("""
        Could not find the `path.join(__dirname, "...")` icon directory in
        #{plugin_path()}. If the plugin changed how it locates the Heroicons
        package, update this module to read the same location -- do not delete
        it: nothing else verifies that a `hero-` name is one the build emits.
        """)
    end
  end

  defp suffixes(plugin) do
    case Regex.scan(~r/\[\s*"(-?[a-z]*)",\s*"(\/\d+\/[a-z]+)"\s*\]/, plugin,
           capture: :all_but_first
         ) do
      [] ->
        flunk("""
        Could not find the `[suffix, directory]` table in #{plugin_path()}. If
        the plugin changed how it names icons, update this module to derive
        names the same way.
        """)

      suffixes ->
        suffixes
    end
  end

  defp svg_files(dir) do
    case Path.wildcard(Path.join(dir, "*.svg")) do
      [] ->
        flunk("""
        No Heroicons SVGs found in #{Path.relative_to(dir, @workspace)}. The
        Heroicons dependency is fetched by `mix deps.get`; without it neither
        the Tailwind build nor this module can know which icons exist.
        """)

      files ->
        files
    end
  end
end
