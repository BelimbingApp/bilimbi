defmodule Bilimbi.Base.UI.DesignLibraryImitationTest do
  @moduledoc """
  The Design Library must not present hand-written markup as if it were a
  shared component. A reviewer who sees "Tabs" in the library assumes a
  `<.tabs>` exists; when it does not, the library is lying about what the
  product can build.

  Three shapes are mechanically detectable. All three rules are owned by
  `Bilimbi.Base.UI.DesignLibrarySource` and exercised on fixtures by
  `Bilimbi.Base.UI.DesignLibraryRulesTest`:

    * **A `component-*` anchor with no component behind it.** The library
      marks what it presents with `id="component-<name>"`. Only the grouping
      sections the sidebar menu links to, the wrapper around them and the menu
      itself are exempt. Every other `component-*` anchor must name a public
      component and call it.
    * **Control markup or interaction attributes.** Inside the components
      area, raw `<nav>`, `<a>`, `<input>`, `<dl>` and the other control tags
      are what shared components render, and so are raw elements carrying
      interaction state such as `aria-current` or `role`. The theme, graphic
      and design-spec areas are reference surfaces that claim no component, so
      only the components area is checked.
    * **An undeclared `<.card>` in the components area.** A card frames a
      specimen, so one carrying no `component-` anchor — id-less or under a
      library id of its own — presents something the library never names. It
      has to be anchored, sit inside an anchored block, or be listed in
      `@declared_specimens`.

  What this does not catch: a fake built from raw non-card, non-control markup
  that takes no anchor — styled `<div>`s directly inside a grouping section,
  with no interaction attribute — is invisible to all three rules. Catching
  that needs a convention the library does not have yet.

  These guards are excluded from the default run until the Design Library
  specimens they report are corrected. Run them with
  `mix test --include design_library_drift`.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.DesignLibrarySource, as: Source

  @moduletag :design_library_drift

  setup_all do
    tree = Source.tree()

    assert :components in Enum.map(Source.areas(tree), &elem(&1, 0)),
           floor_failure("has no `if @area == :components do` block")

    assert Source.presented(tree) != [], floor_failure("presents no element at all")

    %{tree: tree}
  end

  test "every component-* anchor names a shared component that its block presents", ctx do
    problems = Source.anchor_problems(ctx.tree)

    assert problems == [],
           """
           These `component-*` anchors in #{Path.relative_to_cwd(Source.path())}
           present something that is not a shared component:

           #{Enum.map_join(problems, "\n", &("  " <> &1))}

           The `component-` prefix is the library's claim that a block presents
           a shared component from Bilimbi.Base.UI.Components, and the claim
           holds only when the block calls it. The exemption is narrow: a
           grouping section carries the prefix for a heading rather than a
           component, and it earns the exemption by being linked from the
           sidebar menu. A new grouping section has to be linked from the menu
           or drop the prefix; a block that is guidance or scaffolding drops
           the prefix; and a component that does not exist yet gets built
           before it is shown.
           """
  end

  test "every card specimen says what it presents", ctx do
    problems = Source.specimen_problems(ctx.tree)

    assert problems == [],
           """
           The Design Library's specimen declarations and its
           #{Path.relative_to_cwd(Source.path())} cards disagree:

           #{Enum.map_join(problems, "\n", &("  " <> &1))}

           A `<.card>` in the components area frames a specimen, so one with no
           `component-<name>` anchor claims to present something without saying
           what. Anchor it, nest it inside the block that is anchored, or admit
           it in `@declared_specimens`. A declaration that matches no card has
           outlived its reason and goes.
           """
  end

  test "no specimen is built from hand-written control markup", ctx do
    problems = Source.control_problems(ctx.tree)

    assert problems == [],
           """
           These raw elements in #{Path.relative_to_cwd(Source.path())} build
           a control by hand inside the Design Library:

           #{Enum.map_join(problems, "\n", &("  " <> &1))}

           Structural and control markup in the library must come from a
           shared component, so the library shows what the product can build
           and nothing else. Render it through the component that owns it, or
           build that component in Bilimbi.Base.UI.Components before showing
           it here. The sidebar menu is the library's own navigation and is
           not checked.
           """
  end

  # Both guards pass when they find nothing wrong, so an empty read is
  # indistinguishable from a clean library. Assert the tree yielded the
  # surface under test before trusting either verdict.
  defp floor_failure(symptom) do
    """
    #{Path.relative_to_cwd(Source.path())} #{symptom}, so these guards would
    report a clean library without reading a single specimen. Either the
    template abandoned the `if @area == …` convention that
    Bilimbi.Base.UI.DesignLibrarySource derives areas from, or that module can
    no longer read the parser's output. Fix the reader before trusting the
    guards.
    """
  end
end
