defmodule BilimbiWeb.MenuIconSafelistTest do
  @moduledoc """
  Menu icons are supplied by module contributions at runtime, but Tailwind can
  only emit utilities for class names it sees literally at build time. `app.css`
  therefore safelists them with `@source inline(...)`.

  That list is a copy of state that lives somewhere else, and its failure mode is
  invisible: contribute a menu item with a new icon and nothing breaks -- no test,
  no gate -- the icon is simply missing from the sidebar rail. This test is the
  gate that makes that drift loud.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.Menu
  alias Bilimbi.Base.UI.IconRegistry

  @app_css Path.expand("../../assets/css/app.css", __DIR__)

  test "every contributed menu icon is safelisted in app.css" do
    safelisted = safelisted_icons()

    missing =
      contributed_heroicons()
      |> Enum.reject(&(&1 in safelisted))
      |> Enum.sort()

    assert missing == [],
           """
           Menu contributions declare icons that app.css does not safelist, so
           Tailwind will not emit their utilities and they will be missing from
           the sidebar rail:

               #{Enum.join(missing, ", ")}

           Add them to the `@source inline("hero-{...}")` list in
           apps/web/assets/css/app.css.
           """
  end

  test "app.css does not safelist icons no module contributes" do
    contributed = contributed_heroicons()

    stale = safelisted_icons() |> Enum.reject(&(&1 in contributed)) |> Enum.sort()

    assert stale == [],
           """
           app.css safelists icons that no menu contribution declares, so Tailwind
           is emitting utilities nothing uses:

               #{Enum.join(stale, ", ")}

           Remove them from the `@source inline("hero-{...}")` list in
           apps/web/assets/css/app.css.
           """
  end

  # Registry icons are inline SVG rendered by `IconRegistry`, not Tailwind
  # utilities, so they need no `hero-` safelist entry -- and demanding one would
  # fail a contribution that is entirely correct. Only Heroicon names are the
  # safelist's business.
  defp contributed_heroicons do
    Menu.items()
    |> Enum.map(& &1.icon)
    |> Enum.reject(&(is_nil(&1) or match?({:ok, _icon}, IconRegistry.fetch(&1))))
    |> Enum.uniq()
  end

  # Parsed rather than hand-listed: a fixture copy of the safelist would be a
  # third copy of the same state, which is the problem this test exists to catch.
  defp safelisted_icons do
    css = File.read!(@app_css)

    case Regex.run(~r/@source inline\("hero-\{([^}]*)\}"\)/, css, capture: :all_but_first) do
      [names] ->
        names |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

      nil ->
        flunk("""
        Could not find a `@source inline("hero-{...}")` safelist in #{@app_css}.

        If the safelist moved or changed shape, update this test to match -- do
        not delete it: menu icons are supplied at runtime and Tailwind cannot
        see them without a literal list.
        """)
    end
  end
end
