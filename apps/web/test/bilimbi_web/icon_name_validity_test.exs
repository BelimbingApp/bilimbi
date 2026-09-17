defmodule BilimbiWeb.IconNameValidityTest do
  @moduledoc """
  `<.icon>` renders a Heroicon as `<span class="hero-…">`, and it does so for
  any `hero-` name at all. A registry action mapped to a misspelled Heroicon and
  a glyph renamed or removed upstream both render the same span with no CSS
  behind it, so the screen shows nothing where the icon belongs. Neither the
  registry nor the component can tell, and a test that restates the registry map
  cannot either.

  `BilimbiWeb.HeroiconsManifest` derives the accepted names from the manifest
  the Tailwind build itself consumes, so they never come from a list anyone
  maintains by hand. Both halves of the registry's named vocabulary are held to
  it through the public API: the action names of `IconRegistry.actions/0` and
  the shell meanings of `IconRegistry.shell_actions/0`. Call sites that bypass
  the registry and pass a `hero-` name straight through are outside this check.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.IconRegistry
  alias BilimbiWeb.HeroiconsManifest

  test "every registry action resolves to a Heroicon the build can emit" do
    heroicons = HeroiconsManifest.names()

    missing =
      IconRegistry.actions()
      |> Enum.reject(fn {_action, hero_name} -> MapSet.member?(heroicons, hero_name) end)
      |> Enum.sort()

    assert missing == [],
           """
           IconRegistry maps actions to Heroicon names that
           #{HeroiconsManifest.plugin_path()} cannot emit, so those actions
           render an empty span:

           #{format_pairs(missing)}

           Check the spelling against deps/heroicons/optimized, or choose a
           glyph the pinned Heroicons release still ships.
           """
  end

  test "every shell action resolves to a Heroicon the build can emit" do
    heroicons = HeroiconsManifest.names()

    missing =
      IconRegistry.shell_actions()
      |> Enum.reject(fn {_action, hero_name} -> MapSet.member?(heroicons, hero_name) end)
      |> Enum.sort()

    assert missing == [],
           """
           IconRegistry maps shell actions to Heroicon names that
           #{HeroiconsManifest.plugin_path()} cannot emit, so the top bar, the
           account menu and Design Library render an empty span for them:

           #{format_pairs(missing)}

           Check the spelling against deps/heroicons/optimized, or choose a
           glyph the pinned Heroicons release still ships.
           """
  end

  defp format_pairs(pairs) do
    Enum.map_join(pairs, "\n", fn {action, hero_name} -> "    #{action} => #{hero_name}" end)
  end
end
