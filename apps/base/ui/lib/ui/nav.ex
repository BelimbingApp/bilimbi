defmodule Bilimbi.Base.UI.Nav do
  @moduledoc """
  The navigation tree as the sidebar renders it.

  `Bilimbi.Base.Menu` answers what installed modules *declare*; this module
  answers what this deployment can actually *show*. The two differ because a
  module may contribute a menu item before its screens exist — the menu is
  data, the routes are code, and they land in separate pull requests.

  Rendering a link to a path nothing serves gives the user a 404 they find by
  clicking, which is worse than an absent link. So an item is dropped unless
  its route is one `~p` would verify, and a section is dropped once nothing
  under it survives — the same rule `Menu.visible_tree/1` already applies to
  capabilities, so a section hidden by permission and one hidden by missing
  screens disappear identically. The menu grows into its declared shape as
  each module lands its routes, with no second list to update.
  """

  alias Bilimbi.Base.Menu
  alias Bilimbi.Base.UI.RouteContract

  @type node_t :: Menu.node_t()

  @doc """
  The tree `scope` may see, limited to routes this deployment serves.

  Returns `[]` when no contribution snapshot is installed, so a layout rendered
  before the deployment application boots — or in an isolated component test —
  shows no navigation rather than crashing the page.
  """
  @spec tree(map() | nil) :: [node_t()]
  def tree(scope) do
    Menu.visible_tree(fn capability -> allowed?(scope, capability) end)
    |> reject_unreachable()
  rescue
    ArgumentError -> []
  end

  @doc """
  Whether `path` is a route this deployment serves.

  The check `~p` performs at compile time, asked at runtime: menu paths arrive
  as data and cannot be verified when this module is compiled.
  """
  @spec served?(String.t()) :: boolean()
  def served?(path) when is_binary(path) do
    RouteContract.verified_route?([], String.split(path, "/", trim: true))
  end

  defp reject_unreachable(nodes) do
    nodes
    |> Enum.map(fn node -> %{node | children: reject_unreachable(node.children)} end)
    |> Enum.reject(&unreachable?/1)
  end

  # A node survives on either merit: it leads somewhere, or something under it
  # does.
  defp unreachable?(%{item: %{route: nil}, children: children}), do: children == []

  defp unreachable?(%{item: %{route: route}, children: children}),
    do: children == [] and not served?(route)

  defp allowed?(%{capabilities: caps}, cap) when is_list(caps) and is_binary(cap),
    do: cap in caps

  defp allowed?(_scope, _cap), do: false
end
