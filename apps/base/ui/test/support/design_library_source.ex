defmodule Bilimbi.Base.UI.DesignLibrarySource do
  @moduledoc """
  Reads the Design Library template as a tree so the drift guards can reason
  about what the library *presents* instead of which strings it contains.

  The template is parsed with the same parser `Phoenix.LiveView.HTMLFormatter`
  uses, so every element, component call, slot and `<%= if @area == … %>`
  block is available with its line number. On top of that tree this module
  derives, from the template's own conventions and nothing else:

    * **Areas** — the `if @area == :name do` blocks. Everything outside them
      is the library's own chrome (its page container, its header) and is not
      a presentation of anything.
    * **Menu chrome** — the `<aside>` the components area opens with, and
      everything inside it. That is the library navigating itself, not a
      specimen, so its subtree is skipped.
    * **Presented elements** — every element and component call inside an
      area, minus menu chrome. This is what a reviewer sees as "the library".

  Attribute values are normalised to `{:literal, term}` when the template
  spells a value out (a string, `{:info}`, `{false}`, a bare `disabled`) and
  `{:dynamic, code}` otherwise, so guards can tell a presented state from one
  computed at runtime.

  Every node shape the parser can produce is matched explicitly. An unknown
  one raises rather than being skipped, because a silently dropped subtree
  would let the guards pass on a library they never read.
  """

  alias Phoenix.LiveView.TagEngine.Parser

  @path Path.expand("../../lib/ui/web/design_library_live.html.heex", __DIR__)

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

  @doc "Path of the template every guard reads."
  def path, do: @path

  @doc "The parsed template."
  def tree do
    %Parser{nodes: nodes} =
      Parser.parse!(File.read!(@path), tag_handler: Phoenix.LiveView.HTMLEngine, file: @path)

    nodes
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
  def presented(nodes \\ tree()) do
    for {area, body} <- areas(nodes),
        element <- flatten(body, area, [], prune_chrome: true),
        do: element
  end

  @doc "Presented component calls with the given name."
  def calls(name, presented \\ presented()) when is_atom(name) do
    string = Atom.to_string(name)
    Enum.filter(presented, &(&1.kind == :component and &1.name == string))
  end

  @doc """
  Every element with an id, anywhere inside an area, chrome included, as an
  element record. Used to audit the `component-*` anchor convention.
  """
  def anchored(nodes \\ tree()) do
    for {area, body} <- areas(nodes),
        element <- flatten(body, area, [], prune_chrome: false),
        is_binary(element.id),
        do: element
  end

  @doc """
  Whether an element is the library's own sidebar menu, or sits inside it.

  The menu is the `<aside>` an area opens with: raw layout, outside any
  component call, whose job is navigating the library rather than presenting
  anything. Nothing else is exempt.
  """
  def menu_chrome?(%{ancestors: ancestors} = element) do
    Enum.any?([element | ancestors], &menu_container?/1)
  end

  @doc "Every element nested under the given one, in source order."
  def descendants(%{children: children, area: area, ancestors: ancestors} = element) do
    flatten(children, area, ancestors ++ [element], prune_chrome: false)
  end

  @doc "The normalised value of an attribute, or `nil` when it is not given."
  def attr(%{attrs: attrs}, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  @doc "The named slots given directly to a component call."
  def slots(%{children: children}, slot_name) when is_binary(slot_name) do
    for {:block, :slot, ^slot_name, attrs, kids, meta, _} <- children,
        do: element(:slot, slot_name, attrs, kids, meta)
  end

  @doc """
  Whether a component call passes an inner block: any child that is neither a
  named slot nor whitespace.
  """
  def inner_block?(%{children: children}) do
    Enum.any?(children, fn
      {:block, :slot, _, _, _, _, _} -> false
      {:text, text, _} -> String.trim(text) != ""
      _ -> true
    end)
  end

  ## Tree walking

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
        {:eex_comment, _, _} -> acc
        other -> unknown_node!(other)
      end
    end)
  end

  defp flatten(nodes, area, ancestors, opts) do
    prune? = Keyword.fetch!(opts, :prune_chrome)

    Enum.flat_map(nodes, fn
      {:block, type, name, attrs, children, meta, _} ->
        element = element(type, name, attrs, children, meta, area, ancestors)

        if prune? and menu_chrome?(element) do
          []
        else
          [element | flatten(children, area, ancestors ++ [element], opts)]
        end

      {:self_close, type, name, attrs, meta} ->
        [element(type, name, attrs, [], meta, area, ancestors)]

      {:eex_block, _, clauses, _} ->
        Enum.flat_map(clauses, fn {body, _, _} -> flatten(body, area, ancestors, opts) end)

      {:text, _, _} ->
        []

      {:eex, _, _} ->
        []

      {:body_expr, _, _} ->
        []

      {:eex_comment, _, _} ->
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
