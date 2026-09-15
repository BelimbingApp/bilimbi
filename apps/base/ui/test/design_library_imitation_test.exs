defmodule Bilimbi.Base.UI.DesignLibraryImitationTest do
  @moduledoc """
  The Design Library must not present hand-written markup as if it were a
  shared component. A reviewer who sees "Tabs" in the library assumes a
  `<.tabs>` exists; when it does not, the library is lying about what the
  product can build.

  Two things make an imitation detectable without a hand-maintained list:

    * **The anchor convention.** The library marks what it presents with
      `id="component-<name>"`. Sections (`<section id="component-inputs">`),
      the wrapper around them and the sidebar menu are recognised from the
      tree. Every other `component-*` anchor must name a public component,
      and the block it anchors must actually call it.
    * **Control markup is component-owned.** Inside the areas, raw `<nav>`,
      `<a>`, `<input>`, `<dl>` and the other tags below are what shared
      components render, so hand-writing them in a specimen is by definition
      building a component by hand. The same goes for raw elements carrying
      interaction state such as `aria-current` or `phx-click`.

  Adding a fifth fake component trips one of these without anyone updating a
  list: it either takes a `component-*` anchor with no component behind it, or
  it is built from control markup.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.Components
  alias Bilimbi.Base.UI.DesignLibrarySource, as: Source

  # Tags that only shared components may render inside a specimen. Each has a
  # shared component that owns it, or names a control the product has not
  # built yet, which is exactly when an imitation appears.
  @control_tags ~w(a button dl fieldset form header input label nav select table textarea)

  # Attributes that turn a raw element into a hand-written control.
  @control_attrs ~w(aria-current aria-expanded aria-pressed aria-selected phx-change phx-click
                    phx-submit role tabindex)

  setup_all do
    tree = Source.tree()
    %{tree: tree, presented: Source.presented(tree), section_ids: Source.section_ids(tree)}
  end

  test "every component-* anchor names a shared component that its block presents", ctx do
    problems =
      ctx.tree
      |> Source.anchored()
      |> Enum.filter(&String.starts_with?(&1.id, "component-"))
      |> Enum.flat_map(&anchor_problem(&1, ctx.section_ids))

    assert problems == [],
           """
           These `component-*` anchors in #{Path.relative_to_cwd(Source.path())}
           present something that is not a shared component:

           #{Enum.map_join(problems, "\n", &("  " <> &1))}

           The `component-` prefix is the library's claim that a block presents
           a shared component from Bilimbi.Base.UI.Components. Sections, their
           wrapper and the sidebar menu are recognised from the tree. Anything
           else must name a public component and call it. If the component does
           not exist, build it first; if the block is guidance or scaffolding,
           drop the prefix.
           """
  end

  test "no specimen is built from hand-written control markup", ctx do
    problems =
      ctx.presented
      |> Enum.filter(&(&1.kind == :tag))
      |> Enum.flat_map(&control_problem/1)

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

  ## Anchors

  defp anchor_problem(element, section_ids) do
    slug = String.replace_prefix(element.id, "component-", "")

    cond do
      element.kind == :tag and element.name == "section" ->
        []

      wraps_section?(element) ->
        []

      Source.menu_chrome?(element, section_ids) ->
        []

      true ->
        case component_for(slug) do
          nil ->
            [
              "##{element.id} (line #{element.line}) claims <.#{String.replace(slug, "-", "_")}>, " <>
                "which is not a public component"
            ]

          component ->
            if presents?(element, component),
              do: [],
              else: [
                "##{element.id} (line #{element.line}) claims <.#{component}> but never calls it"
              ]
        end
    end
  end

  defp wraps_section?(element) do
    Enum.any?(Source.descendants(element), &(&1.kind == :tag and &1.name == "section"))
  end

  # `component-icon-button` names `icon_button`; `component-input-states` is
  # the `input` specimen qualified by what it shows. Longest match wins so a
  # qualified anchor still has to present the component it names.
  defp component_for(slug) do
    names = public_component_names()

    slug
    |> String.split("-")
    |> Enum.scan(&(&2 <> "_" <> &1))
    |> Enum.reverse()
    |> Enum.find(&(&1 in names))
    |> then(&(&1 && String.to_atom(&1)))
  end

  # A heading carrying the anchor names the section it heads; anything else
  # presents what it contains.
  defp presents?(%{kind: :tag, name: <<"h", digit>>} = heading, component)
       when digit in ?1..?6 do
    section =
      heading.ancestors
      |> Enum.reverse()
      |> Enum.find(&(&1.kind == :tag and &1.name == "section"))

    if section, do: presents?(section, component), else: false
  end

  defp presents?(element, component) do
    name = Atom.to_string(component)
    Enum.any?(Source.descendants(element), &(&1.kind == :component and &1.name == name))
  end

  defp public_component_names do
    Components.__components__()
    |> Map.keys()
    |> Enum.filter(&function_exported?(Components, &1, 1))
    |> Enum.map(&Atom.to_string/1)
  end

  ## Control markup

  defp control_problem(%{name: name, line: line, attrs: attrs}) do
    tag = if name in @control_tags, do: ["<#{name}> is rendered by shared components"], else: []

    controls =
      for {attr, _} <- attrs, attr in @control_attrs, do: "`#{attr}` marks a hand-written control"

    for reason <- tag ++ controls, do: "<#{name}> at line #{line}: #{reason}"
  end
end
