defmodule Bilimbi.Base.UI.DesignLibrarySource do
  @moduledoc """
  Reads the Design Library as a tree and owns the conventions its drift guards
  hold it to, so that the guards and their own self-test share one definition
  of every rule.

  A template is parsed with the same parser `Phoenix.LiveView.HTMLFormatter`
  uses, so every element, component call, slot and `<%= if @area == … %>`
  block is available with its line number. On top of that tree this module
  derives, from the library's own conventions and nothing else:

    * **Areas** — the `if @area == :name do` blocks. Everything outside them
      is the library's own chrome (its page container, its header) and is not
      a presentation of anything.
    * **Menu chrome** — the `<aside>` an area opens with, and everything
      inside it. That is the library navigating itself, not a specimen, so
      its subtree is skipped.
    * **Grouping sections** — the `<section>`s that menu links point at. They
      carry the `component-` prefix for a heading rather than a component, so
      they are the one exemption from the anchor rule, and a new one earns the
      exemption by being linked from the menu.
    * **The catalog** — every other `component-<slug>` anchor, resolved to the
      public component its slug names. A component is presented when it has a
      catalog entry of its own that calls it; using it to build some other
      specimen's container is not a presentation of it, for the same reason
      the page chrome is not. A call that is, or sits inside, a nested anchor
      belongs to that nested entry, so an entry never counts the blocks that
      frame its neighbours.
    * **Declared specimens** — an id-less `<.card>` in the components area
      claims to present something without saying what, and carries no control
      markup to catch it. `@declared_specimens` is the library's admission of
      the ones it already has; anything else has to be anchored or added
      there, and a declaration that stops matching is reported so the list
      cannot outlive its reason.

  Attribute values are normalised to `{:literal, term}` when the template
  spells a value out (a string, `{:info}`, `{false}`, a bare `disabled`) and
  `{:dynamic, code}` otherwise, so guards can tell a presented state from one
  computed at runtime.

  Every node shape the parser can produce is matched explicitly. An unknown
  one raises rather than being skipped, because a silently dropped subtree
  would let the guards pass on a library they never read.
  """

  alias Bilimbi.Base.UI.Components
  alias Phoenix.LiveView.TagEngine.Parser

  @path Path.expand("../../lib/ui/web/design_library_live.html.heex", __DIR__)

  # Tags that only shared components may render inside a specimen. Each has a
  # shared component that owns it, or names a control the product has not
  # built yet, which is exactly when an imitation appears.
  @control_tags ~w(a button dl fieldset form header input label nav select table textarea)

  # Attributes that give a raw element the behaviour of a control. A tabs fake
  # built from styled `<div>`s carries no control tag and is caught only here.
  @control_attrs ~w(aria-current aria-expanded aria-pressed aria-selected phx-change phx-click
                    phx-submit role tabindex)

  # The id-less specimen cards the components area presents today, keyed by the
  # card's literal `title`, or for an untitled card by the literal id of its
  # first identified descendant. Keys are template facts, not line numbers, so
  # moving a specimen does not churn this list while renaming one does.
  @declared_specimens [
    "Text and long-form inputs",
    "Choice controls",
    "Date, time, and secret inputs",
    "Empty workspace",
    "Permission denied",
    "Connection interrupted",
    "design-library-pattern-table"
  ]

  @type element :: %{
          kind: :tag | :component | :remote_component | :slot,
          name: String.t(),
          attrs: [{String.t(), {:literal, term()} | {:dynamic, String.t()}}],
          id: String.t() | nil,
          line: pos_integer(),
          children: list(),
          area: atom() | nil,
          ancestors: [map()]
        }

  @doc "Path of the template the drift guards read."
  def path, do: @path

  @doc "Parses a HEEx template into parser nodes."
  def parse(template, file \\ "nofile") when is_binary(template) do
    %Parser{nodes: nodes} =
      Parser.parse!(template, tag_handler: Phoenix.LiveView.HTMLEngine, file: file)

    nodes
  end

  @doc "The parsed Design Library template."
  def tree, do: parse(File.read!(@path), @path)

  @doc "Public components, the vocabulary every guard measures the library against."
  def public_components do
    Components.__components__()
    |> Map.keys()
    |> Enum.filter(&function_exported?(Components, &1, 1))
    |> Enum.sort()
  end

  @doc """
  The `if @area == :name do` blocks of the template as `{area, nodes}` pairs,
  in source order.
  """
  def areas(nodes \\ tree()) do
    collect(nodes, [], fn
      {:eex_block, expr, [{body, _, _}], _} ->
        case Regex.run(~r/\Aif @area == :(\w+) do\z/, String.trim(expr)) do
          [_, area] -> [{String.to_atom(area), body}]
          nil -> []
        end

      _ ->
        []
    end)
  end

  @doc """
  Every element and component call the library presents: everything inside an
  area, minus menu chrome, flattened in source order. Each element carries its
  `area` and its `ancestors` (outermost first) so a guard can ask where it sits.
  """
  def presented(nodes \\ tree()), do: elements(nodes, true)

  @doc """
  Every element with an id, anywhere inside an area, chrome included, as an
  element record. Used to audit the `component-*` anchor convention.
  """
  def anchored(nodes \\ tree()) do
    nodes |> elements(false) |> Enum.filter(&is_binary(&1.id))
  end

  @doc """
  Whether an element is the library's own sidebar menu, or sits inside it.

  The menu is the `<aside>` an area opens with: raw layout, outside any
  component call, whose job is navigating the library rather than presenting
  anything.
  """
  def menu_chrome?(%{ancestors: ancestors} = element) do
    Enum.any?([element | ancestors], &menu_container?/1)
  end

  @doc "The ids the sidebar menu links to, which is what makes a section a grouping."
  def menu_targets(nodes \\ tree()) do
    for element <- elements(nodes, false),
        menu_chrome?(element),
        element.kind == :tag,
        element.name == "a",
        {:literal, "#" <> id} <- [attr(element, "href")],
        into: MapSet.new(),
        do: id
  end

  @doc """
  The library's catalog as `{component, entry}` pairs: every `component-<slug>`
  anchor whose slug names a public component, paired with the block that
  anchor marks. A heading carrying the anchor marks the section it heads.
  """
  def catalog(nodes \\ tree()) do
    targets = menu_targets(nodes)

    for element <- anchored(nodes),
        String.starts_with?(element.id, "component-"),
        not menu_chrome?(element),
        not grouping_section?(element, targets),
        component = component_for(component_slug(element)),
        component != nil,
        do: {component, entry_element(element)}
  end

  @doc "Calls to `component` inside the catalog entries that claim to present it."
  def entry_calls(component, catalog) when is_atom(component) do
    name = Atom.to_string(component)

    Enum.flat_map(catalog, fn
      {^component, entry} -> entry_calls_within(entry, name)
      _other -> []
    end)
  end

  @doc """
  Anchors whose `component-` prefix claims something the library does not
  present, as one sentence each.
  """
  def anchor_problems(nodes \\ tree()) do
    targets = menu_targets(nodes)

    nodes
    |> anchored()
    |> Enum.filter(&String.starts_with?(&1.id, "component-"))
    |> Enum.flat_map(&anchor_problem(&1, targets))
  end

  @doc """
  Raw elements inside the components area that build a control by hand, as one
  sentence each.
  """
  def control_problems(nodes \\ tree()) do
    nodes
    |> presented()
    |> Enum.filter(&(&1.kind == :tag and &1.area == :components))
    |> Enum.flat_map(&control_problem/1)
  end

  @doc """
  Specimen cards the library presents without naming, and declarations that no
  longer match one, as one sentence each.
  """
  def specimen_problems(nodes \\ tree()) do
    entry_ids = nodes |> catalog() |> MapSet.new(fn {_component, entry} -> entry.id end)

    candidates =
      nodes
      |> presented()
      |> Enum.filter(&specimen_candidate?(&1, entry_ids))

    declared = MapSet.new(candidates, &specimen_key/1)

    undeclared =
      for card <- candidates, specimen_key(card) not in @declared_specimens, do: undeclared(card)

    stale =
      for key <- @declared_specimens, not MapSet.member?(declared, key), do: stale(key)

    undeclared ++ stale
  end

  @doc "Every element nested under the given one, in source order."
  def descendants(%{children: children, area: area, ancestors: ancestors} = element) do
    flatten(children, area, ancestors ++ [element], false)
  end

  @doc "The normalised value of an attribute, or `nil` when it is not given."
  def attr(%{attrs: attrs}, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  @doc "The named slots given directly to a component call, self-closing ones included."
  def slots(%{children: children}, slot_name) when is_binary(slot_name) do
    Enum.flat_map(children, fn
      {:block, :slot, ^slot_name, attrs, kids, meta, _} ->
        [element(:slot, slot_name, attrs, kids, meta)]

      {:self_close, :slot, ^slot_name, attrs, meta} ->
        [element(:slot, slot_name, attrs, [], meta)]

      _other ->
        []
    end)
  end

  @doc """
  Whether a component call passes an inner block: any child that is neither a
  named slot nor whitespace.
  """
  def inner_block?(%{children: children}) do
    Enum.any?(children, fn
      {:block, :slot, _, _, _, _, _} -> false
      {:self_close, :slot, _, _, _} -> false
      {:text, text, _} -> String.trim(text) != ""
      _other -> true
    end)
  end

  ## The anchor convention

  defp anchor_problem(element, targets) do
    cond do
      menu_chrome?(element) -> []
      grouping_section?(element, targets) -> []
      wraps_grouping_section?(element, targets) -> []
      true -> claim_problem(element)
    end
  end

  defp grouping_section?(%{kind: :tag, name: "section", id: id}, targets) when is_binary(id) do
    MapSet.member?(targets, id)
  end

  defp grouping_section?(_element, _targets), do: false

  defp wraps_grouping_section?(element, targets) do
    Enum.any?(descendants(element), &grouping_section?(&1, targets))
  end

  defp claim_problem(element) do
    slug = component_slug(element)

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

  defp component_slug(%{id: "component-" <> slug}), do: slug

  # `component-icon-button` names `icon_button`; `component-input-states` is
  # the `input` specimen qualified by what it shows. Longest match wins so a
  # qualified anchor still has to present the component it names.
  defp component_for(slug) do
    names = Enum.map(public_components(), &Atom.to_string/1)

    slug
    |> String.split("-")
    |> Enum.scan(&(&2 <> "_" <> &1))
    |> Enum.reverse()
    |> Enum.find(&(&1 in names))
    |> then(&(&1 && String.to_atom(&1)))
  end

  defp presents?(element, component) do
    entry_calls_within(entry_element(element), Atom.to_string(component)) != []
  end

  # A nested anchor is its own entry, whether or not the component it claims
  # exists. Excluding it, and everything under it, is what keeps a
  # heading-anchored section from counting the cards that frame its
  # neighbouring specimens as presentations of `card`.
  defp entry_calls_within(entry, name) do
    descendants = descendants(entry)
    nested = for anchor <- descendants, anchor_claim?(anchor), into: MapSet.new(), do: anchor.id

    [entry | descendants]
    |> Enum.filter(&(&1.kind == :component and &1.name == name))
    |> Enum.reject(&framed_by?(&1, nested))
  end

  defp framed_by?(element, nested) do
    Enum.any?(
      [element | element.ancestors],
      &(is_binary(&1.id) and MapSet.member?(nested, &1.id))
    )
  end

  # A heading carrying the anchor marks the section it heads; anything else
  # marks what it contains.
  defp entry_element(%{kind: :tag, name: <<"h", digit>>} = heading) when digit in ?1..?6 do
    heading.ancestors
    |> Enum.reverse()
    |> Enum.find(heading, &(&1.kind == :tag and &1.name == "section"))
  end

  defp entry_element(element), do: element

  ## Declared specimens

  defp specimen_candidate?(element, entry_ids) do
    element.kind == :component and element.name == "card" and element.area == :components and
      not anchor_claim?(element) and
      not Enum.any?(element.ancestors, &(is_binary(&1.id) and MapSet.member?(entry_ids, &1.id)))
  end

  defp anchor_claim?(%{id: "component-" <> _slug}), do: true
  defp anchor_claim?(_element), do: false

  defp specimen_key(card) do
    case attr(card, "title") do
      {:literal, title} when is_binary(title) -> title
      _other -> card |> descendants() |> Enum.find_value(& &1.id)
    end
  end

  defp undeclared(card) do
    "<.card> at line #{card.line} (#{key_label(specimen_key(card))}) presents a specimen the " <>
      "library never names: anchor it as a `component-<name>` entry, or declare it in " <>
      "@declared_specimens"
  end

  defp stale(key) do
    "declared specimen #{inspect(key)} matches no id-less <.card> in the components area; " <>
      "drop the declaration"
  end

  defp key_label(nil), do: "no title and no identified content"
  defp key_label(key), do: inspect(key)

  ## Control markup

  defp control_problem(element) do
    case control_reason(element) do
      nil -> []
      reason -> ["<#{element.name}> at line #{element.line}: #{reason}"]
    end
  end

  defp control_reason(%{name: name}) when name in @control_tags do
    "<#{name}> is markup a shared component owns"
  end

  defp control_reason(%{attrs: attrs}) do
    case Enum.find(attrs, fn {attr, _value} -> attr in @control_attrs end) do
      {attr, _value} -> "`#{attr}` gives it the behaviour of a control"
      nil -> nil
    end
  end

  ## Tree walking

  defp elements(nodes, prune_chrome?) do
    for {area, body} <- areas(nodes),
        element <- flatten(body, area, [], prune_chrome?),
        do: element
  end

  defp menu_container?(%{kind: :tag, name: "aside", ancestors: ancestors}) do
    Enum.all?(ancestors, &(&1.kind == :tag))
  end

  defp menu_container?(_element), do: false

  defp collect(nodes, acc, fun) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, acc ->
      acc = acc ++ fun.(node)

      case node do
        {:block, _, _, _, children, _, _} -> collect(children, acc, fun)
        {:eex_block, _, clauses, _} -> Enum.reduce(clauses, acc, &collect(elem(&1, 0), &2, fun))
        {:self_close, _, _, _, _} -> acc
        {:text, _, _} -> acc
        {:eex, _, _} -> acc
        {:body_expr, _, _} -> acc
        {:eex_comment, _} -> acc
        other -> unknown_node!(other)
      end
    end)
  end

  defp flatten(nodes, area, ancestors, prune_chrome?) do
    Enum.flat_map(nodes, fn
      {:block, type, name, attrs, children, meta, _} ->
        element = element(type, name, attrs, children, meta, area, ancestors)

        if prune_chrome? and menu_chrome?(element) do
          []
        else
          [element | flatten(children, area, ancestors ++ [element], prune_chrome?)]
        end

      {:self_close, type, name, attrs, meta} ->
        [element(type, name, attrs, [], meta, area, ancestors)]

      {:eex_block, _, clauses, _} ->
        Enum.flat_map(clauses, fn {body, _, _} ->
          flatten(body, area, ancestors, prune_chrome?)
        end)

      {:text, _, _} ->
        []

      {:eex, _, _} ->
        []

      {:body_expr, _, _} ->
        []

      {:eex_comment, _} ->
        []

      other ->
        unknown_node!(other)
    end)
  end

  defp unknown_node!(node) do
    raise """
    #{inspect(__MODULE__)} does not recognise this node of \
    #{Path.relative_to_cwd(@path)}:

        #{inspect(node)}

    It walks Phoenix.LiveView.TagEngine.Parser output. Skipping an unknown \
    shape would drop a subtree of the Design Library and let its drift guards \
    pass on markup they never read, so teach this module the new shape instead.
    """
  end

  defp element(type, name, attrs, children, meta, area \\ nil, ancestors \\ []) do
    attrs = normalise_attrs(attrs)

    %{
      kind: kind(type),
      name: name,
      attrs: attrs,
      id: literal(List.keyfind(attrs, "id", 0)),
      line: meta.line,
      children: children,
      area: area,
      ancestors: ancestors
    }
  end

  defp kind(:tag), do: :tag
  defp kind(:local_component), do: :component
  defp kind(:remote_component), do: :remote_component
  defp kind(:slot), do: :slot

  defp literal({_, {:literal, value}}) when is_binary(value), do: value
  defp literal(_), do: nil

  defp normalise_attrs(attrs) do
    for {name, value, _meta} <- attrs, is_binary(name), do: {name, normalise_value(value)}
  end

  defp normalise_value(nil), do: {:literal, true}
  defp normalise_value({:string, string, _}), do: {:literal, string}

  defp normalise_value({:expr, code, _}) do
    case Code.string_to_quoted(code) do
      {:ok, value} when is_atom(value) or is_binary(value) or is_number(value) ->
        {:literal, value}

      _ ->
        {:dynamic, String.trim(code)}
    end
  end
end
