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

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @type node_t :: Menu.node_t()

  @stash {__MODULE__, :rendered_tree}
  @builds {__MODULE__, :builds}

  @doc """
  The tree `scope` may see, limited to routes this deployment serves.

  Returns `[]` when no contribution snapshot is installed, so a layout rendered
  before the deployment application boots — or in an isolated component test —
  shows no navigation rather than crashing the page.

  Layouts call `rendered_tree/1`, not this. This rebuilds the tree every time.
  """
  @spec tree(map() | nil) :: [node_t()]
  def tree(scope) do
    Process.put(@builds, build_count() + 1)

    Menu.visible_tree(fn capability -> Bilimbi.Base.UI.allowed?(scope, capability) end)
    |> reject_unreachable()
  rescue
    ArgumentError -> []
  end

  @doc false
  def build_count, do: Process.get(@builds, 0)

  @doc """
  The tree for `scope`, computed at most once per process until capabilities
  or pins change.

  `on_mount/4` stores it on the LiveView. The shell reads it back through
  here, including a render that did not pass the assign, so a page template
  does not have to thread it. A framed scope skips the work: that render has
  no sidebar. Pins are part of the key when the scope already carries them;
  building the tree does not load pins.
  """
  @spec rendered_tree(map() | nil) :: [node_t()]
  def rendered_tree(scope) do
    key = cache_key(scope)
    cached = Process.get(@stash)

    case cached do
      {^key, nav} when is_list(nav) ->
        nav

      _else ->
        nav = tree(scope)
        Process.put(@stash, {key, nav})
        nav
    end
  end

  @doc false
  def on_mount(:prepare, _params, _session, socket) do
    socket =
      socket
      |> refresh()
      |> attach_hook(:nav_tree_params, :handle_params, fn _params, _uri, socket ->
        {:cont, refresh(socket)}
      end)
      |> attach_hook(:nav_tree_event, :handle_event, fn _event, _params, socket ->
        {:cont, refresh(socket)}
      end)

    {:cont, socket}
  end

  @doc false
  def refresh(%{assigns: assigns} = socket) do
    scope = assigns[:current_scope]

    if framed?(scope) do
      socket
    else
      key = cache_key(scope)

      if assigns[:nav_key] == key and is_list(assigns[:nav]) do
        Process.put(@stash, {key, assigns.nav})
        socket
      else
        nav = rendered_tree(scope)
        assign(socket, nav: nav, nav_key: key)
      end
    end
  end

  defp framed?(%{framed: true}), do: true
  defp framed?(_scope), do: false

  defp cache_key(scope) when is_map(scope) do
    caps =
      case scope[:capabilities] do
        list when is_list(list) -> Enum.sort(list)
        _else -> []
      end

    {caps, pin_key(scope[:pins])}
  end

  defp cache_key(_scope), do: :none

  defp pin_key(pins) when is_list(pins), do: Enum.map(pins, &pin_id/1)
  defp pin_key(_pins), do: nil

  defp pin_id(%{id: id, sort_order: order}), do: {id, order}
  defp pin_id(%{id: id}), do: id
  defp pin_id(other), do: other

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
    |> Enum.map(&demote_unserved/1)
    |> Enum.sort_by(&String.downcase(&1.item.label))
  end

  # A node survives on either merit: it leads somewhere, or something under it
  # does.
  defp unreachable?(%{item: %{route: nil}, children: children}), do: children == []

  defp unreachable?(%{item: %{route: route}, children: children}),
    do: children == [] and not served?(route)

  # A node kept only for its children keeps its label and loses its link, so it
  # renders as a section heading. Without this it survives the check above and
  # then renders as exactly the 404 that check exists to prevent -- the item is
  # reachable, its own route is not.
  defp demote_unserved(%{item: %{route: route} = item} = node) when is_binary(route) do
    if served?(route), do: node, else: %{node | item: %{item | route: nil}}
  end

  defp demote_unserved(node), do: node
end
