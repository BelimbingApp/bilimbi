defmodule BilimbiWeb.IconNameValidityTest do
  @moduledoc """
  `<.icon>` renders a Heroicon as `<span class="hero-…">`, and it does so for
  any `hero-` name at all. A registry action mapped to a misspelled Heroicon, a
  glyph renamed or removed upstream, and a call site passing through a name the
  package never had all render the same span with no CSS behind it, so the
  screen shows nothing where the icon belongs. Neither the registry nor the
  component can tell, and a test that restates the registry map cannot either.

  Tailwind emits `hero-*` utilities from `assets/vendor/heroicons.js`, which
  reads the SVG files under `deps/heroicons/optimized` and names each one after
  its file plus a per-directory suffix. This test reads the same manifest the
  same way, so the accepted names come from the package the build consumes and
  never from a list anyone maintains by hand.

  Registry entries and pass-through names are held to the same bar. The
  registry's action values are checked through its public API, and every
  literal `hero-` name in module source -- the registry's shell vocabulary, the
  component fallback, and each call site that bypasses the registry -- is
  checked by a sweep of `lib/` across the workspace. A `hero-` name that the
  registry itself serves as inline SVG, such as `hero-impersonate`, resolves
  through the registry and needs no Heroicon.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.IconRegistry

  @plugin Path.expand("../../assets/vendor/heroicons.js", __DIR__)
  @workspace Path.expand("../../../..", __DIR__)
  @source_globs ["apps/*/lib/**/*.{ex,exs,heex}", "apps/*/*/lib/**/*.{ex,exs,heex}"]

  test "every registry action resolves to a Heroicon the build can emit" do
    heroicons = heroicon_names()

    missing =
      IconRegistry.actions()
      |> Enum.reject(fn {_action, hero_name} -> MapSet.member?(heroicons, hero_name) end)
      |> Enum.sort()

    assert missing == [],
           """
           IconRegistry maps actions to Heroicon names that #{plugin_path()} cannot
           emit, so those actions render an empty span:

           #{format_pairs(missing)}

           Check the spelling against deps/heroicons/optimized, or choose a
           glyph the pinned Heroicons release still ships.
           """
  end

  test "every hero- name in module source resolves to a registry glyph or a Heroicon" do
    heroicons = heroicon_names()
    occurrences = source_hero_names()

    swept = occurrences |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    unswept_registry_values =
      IconRegistry.actions() |> Map.values() |> Enum.reject(&MapSet.member?(swept, &1))

    assert unswept_registry_values == [],
           """
           The source sweep did not reach IconRegistry's own action values, so
           its globs no longer cover the registry and cannot be trusted to cover
           call sites either: #{Enum.join(unswept_registry_values, ", ")}
           """

    missing =
      occurrences
      |> Enum.reject(fn {name, _file, _line} ->
        registry_glyph?(name) or MapSet.member?(heroicons, name)
      end)
      |> Enum.group_by(&elem(&1, 0), fn {_name, file, line} -> "#{file}:#{line}" end)
      |> Enum.sort()

    assert missing == [],
           """
           Module source names Heroicons that #{plugin_path()} cannot emit, so
           these icons render an empty span:

           #{format_occurrences(missing)}

           Check the spelling against deps/heroicons/optimized, or choose a
           glyph the pinned Heroicons release still ships.
           """
  end

  defp registry_glyph?(name), do: match?({:ok, _icon}, IconRegistry.fetch(name))

  # Derived the way the Tailwind plugin derives it: the plugin's own icon
  # directory and its per-directory suffix table are parsed out of
  # heroicons.js, then every SVG below each directory becomes one accepted
  # `hero-` name. Copying the four suffixes here instead would make this test
  # a second list to maintain.
  defp heroicon_names do
    plugin = File.read!(@plugin)

    icons_dir =
      case Regex.run(~r/path\.join\(__dirname,\s*"([^"]+)"\)/, plugin, capture: :all_but_first) do
        [relative] ->
          Path.expand(relative, Path.dirname(@plugin))

        nil ->
          flunk("""
          Could not find the `path.join(__dirname, "...")` icon directory in
          #{plugin_path()}. If the plugin changed how it locates the Heroicons
          package, update this test to read the same location -- do not delete
          it: nothing else verifies that a `hero-` name is one the build emits.
          """)
      end

    suffixes =
      Regex.scan(~r/\[\s*"(-?[a-z]*)",\s*"(\/\d+\/[a-z]+)"\s*\]/, plugin, capture: :all_but_first)

    if suffixes == [] do
      flunk("""
      Could not find the `[suffix, directory]` table in #{plugin_path()}. If the
      plugin changed how it names icons, update this test to derive names the
      same way.
      """)
    end

    for [suffix, dir] <- suffixes,
        file <- svg_files(Path.join(icons_dir, dir)),
        into: MapSet.new() do
      "hero-" <> Path.basename(file, ".svg") <> suffix
    end
  end

  defp svg_files(dir) do
    case Path.wildcard(Path.join(dir, "*.svg")) do
      [] ->
        flunk("""
        No Heroicons SVGs found in #{Path.relative_to(dir, @workspace)}. The
        Heroicons dependency is fetched by `mix deps.get`; without it neither
        the Tailwind build nor this test can know which icons exist.
        """)

      files ->
        files
    end
  end

  defp source_hero_names do
    @source_globs
    |> Enum.flat_map(&Path.wildcard(Path.join(@workspace, &1)))
    |> Enum.flat_map(fn file ->
      file
      |> File.stream!()
      |> Stream.with_index(1)
      |> Enum.flat_map(fn {line, number} ->
        ~r/\bhero-[a-z0-9-]+/
        |> Regex.scan(line)
        |> List.flatten()
        |> Enum.map(&{&1, Path.relative_to(file, @workspace), number})
      end)
    end)
  end

  defp plugin_path, do: Path.relative_to(@plugin, @workspace)

  defp format_pairs(pairs) do
    Enum.map_join(pairs, "\n", fn {action, hero_name} -> "    #{action} => #{hero_name}" end)
  end

  defp format_occurrences(missing) do
    Enum.map_join(missing, "\n", fn {name, locations} ->
      "    #{name}\n" <> Enum.map_join(Enum.sort(locations), "\n", &("        " <> &1))
    end)
  end
end
