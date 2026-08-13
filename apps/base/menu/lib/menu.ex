defmodule Bilimbi.Base.Menu do
  @moduledoc """
  Public API for the navigation tree contributed by installed modules.

  Menu items are declared by their owning module through the contribution
  provider, exactly as Belimbing declares them in each module's
  `Config/menu.php`. This module owns validation, ordering and visibility; it
  owns no tables and performs no I/O.

  Visibility is presentation only. `visible_tree/1` hides what an actor may not
  reach, but hiding a link is never authorization — the route must enforce the
  same capability at mount. Belimbing works the same way: the menu filters on
  `permission`, and the route carries `authz:<capability>` middleware.
  """

  alias Bilimbi.Base.Menu.Item
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @type node_t :: %{item: Item.t(), children: [node_t()]}

  @doc "Every validated item, ordered, regardless of visibility."
  @spec items() :: [Item.t()]
  def items, do: ContributionRegistry.consumer!(:menu)

  @doc """
  The full tree, ordered, with no visibility filtering.

  Useful for diagnostics and tests; render `visible_tree/1` instead.
  """
  @spec tree() :: [node_t()]
  def tree, do: build_tree(items())

  @doc """
  The tree an actor may see.

  `allowed?` decides one capability. Pass a function wrapping
  `Bilimbi.Base.Authz.can/4` for the current actor; Menu deliberately does not
  depend on Authz, so the caller supplies the decision.

  Two rules, both taken from Belimbing:

    * an item carrying a capability is hidden unless `allowed?` returns true;
    * a **container is hidden when it has no visible child**, so a section
      never renders as an empty heading. This is also what keeps unported
      Domain roots out of the menu until their modules are installed.
  """
  @spec visible_tree((String.t() -> boolean())) :: [node_t()]
  def visible_tree(allowed?) when is_function(allowed?, 1) do
    items()
    |> Enum.filter(&permitted?(&1, allowed?))
    |> build_tree()
    |> prune_empty_containers()
  end

  @doc "Looks up a validated item by id."
  @spec fetch_item(String.t()) :: {:ok, Item.t()} | :error
  def fetch_item(id) when is_binary(id) do
    case Enum.find(items(), &(&1.id == id)) do
      nil -> :error
      item -> {:ok, item}
    end
  end

  defp permitted?(%Item{capability: nil}, _allowed?), do: true
  defp permitted?(%Item{capability: capability}, allowed?), do: allowed?.(capability)

  defp build_tree(items) do
    by_parent = Enum.group_by(items, & &1.parent)
    children_of(by_parent, nil)
  end

  defp children_of(by_parent, parent) do
    by_parent
    |> Map.get(parent, [])
    |> Enum.map(fn item ->
      %{item: item, children: children_of(by_parent, item.id)}
    end)
  end

  defp prune_empty_containers(nodes) do
    nodes
    |> Enum.map(fn node -> %{node | children: prune_empty_containers(node.children)} end)
    |> Enum.reject(fn node -> Item.container?(node.item) and node.children == [] end)
  end
end
