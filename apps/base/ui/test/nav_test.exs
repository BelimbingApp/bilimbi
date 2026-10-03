defmodule Bilimbi.Base.UI.NavTest do
  @moduledoc """
  The menu declares more than any single deployment serves. These cover the
  gap: what a module contributed, versus what the sidebar may render.
  """

  use ExUnit.Case, async: false

  alias Bilimbi.Base.Menu.Item
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.UI.Nav
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket

  # `/dashboard` is served by the web host, so it is in this app's manifest.
  # Anything under /nowhere never will be.
  @served "/dashboard"
  @unserved "/nowhere/at/all"

  defp install!(items) do
    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "test",
      consumers: %{menu: items}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  defp ids(nodes), do: Enum.map(nodes, & &1.item.id)

  defp scope(caps), do: %{capabilities: caps}

  describe "served?/1" do
    test "agrees with the manifest the route contract was compiled against" do
      assert Nav.served?(@served)
      refute Nav.served?(@unserved)
    end
  end

  describe "tree/1" do
    test "drops a leaf whose route no module serves" do
      install!([
        Item.new!(%{id: "here", label: "Here", route: @served}),
        Item.new!(%{id: "gone", label: "Gone", route: @unserved})
      ])

      assert ids(Nav.tree(scope([]))) == ["here"]
    end

    test "drops a section once every child under it is unserved" do
      install!([
        Item.new!(%{id: "admin", label: "Administration"}),
        Item.new!(%{id: "admin.gone", label: "Gone", parent: "admin", route: @unserved})
      ])

      # Not an empty "Administration" heading: nothing under it leads anywhere.
      assert Nav.tree(scope([])) == []
    end

    test "keeps a section whose surviving child is reachable" do
      install!([
        Item.new!(%{id: "admin", label: "Administration"}),
        Item.new!(%{id: "admin.gone", label: "Gone", parent: "admin", route: @unserved}),
        Item.new!(%{id: "admin.here", label: "Here", parent: "admin", route: @served})
      ])

      assert [%{item: %Item{id: "admin"}, children: children}] = Nav.tree(scope([]))
      assert ids(children) == ["admin.here"]
    end

    test "keeps an unserved item that still leads somewhere through a child" do
      # A parent that is both a link and a section: losing its own screen must
      # not take the reachable screens underneath it with it.
      install!([
        Item.new!(%{id: "top", label: "Top", route: @unserved}),
        Item.new!(%{id: "top.here", label: "Here", parent: "top", route: @served})
      ])

      assert [%{item: %Item{id: "top"}, children: [%{item: %Item{id: "top.here"}}]}] =
               Nav.tree(scope([]))
    end

    test "strips the link from an item kept only for its children" do
      # Surviving on its children is not permission to render its own route:
      # that link is the 404 the pruning exists to prevent.
      install!([
        Item.new!(%{id: "top", label: "Top", route: @unserved}),
        Item.new!(%{id: "top.here", label: "Here", parent: "top", route: @served})
      ])

      assert [%{item: %Item{id: "top", route: nil, label: "Top"}}] = Nav.tree(scope([]))
    end

    test "leaves a served parent's own link intact" do
      install!([
        Item.new!(%{id: "top", label: "Top", route: @served}),
        Item.new!(%{id: "top.here", label: "Here", parent: "top", route: @served})
      ])

      assert [%{item: %Item{id: "top", route: @served}}] = Nav.tree(scope([]))
    end

    test "still hides what the actor lacks the capability for" do
      install!([
        Item.new!(%{id: "open", label: "Open", route: @served}),
        Item.new!(%{
          id: "shut",
          label: "Shut",
          route: @served,
          capability: "admin.user.list"
        })
      ])

      assert ids(Nav.tree(scope([]))) == ["open"]
      assert ids(Nav.tree(scope(["admin.user.list"]))) == ["open", "shut"]
    end

    test "renders nothing rather than crashing when no snapshot is installed" do
      ContributionRegistry.clear_for_test!()

      assert Nav.tree(scope([])) == []
    end

    test "treats a scope carrying no capabilities as an actor with none" do
      install!([
        Item.new!(%{id: "shut", label: "Shut", route: @served, capability: "x"})
      ])

      assert Nav.tree(nil) == []
    end
  end

  describe "rendered_tree/1" do
    test "reuses one tree until capabilities or pins change" do
      install!([
        Item.new!(%{id: "open", label: "Open", route: @served}),
        Item.new!(%{
          id: "shut",
          label: "Shut",
          route: @served,
          capability: "admin.user.list"
        })
      ])

      scope = scope(["admin.user.list"])
      before = Nav.build_count()
      first = Nav.rendered_tree(scope)

      assert Nav.build_count() == before + 1
      assert Nav.rendered_tree(scope) == first
      assert Nav.build_count() == before + 1
      assert ids(first) == ids(Nav.tree(scope))

      narrowed = Nav.rendered_tree(scope([]))
      assert ids(narrowed) == ["open"]
      assert Nav.build_count() == before + 3

      pinned = Map.put(scope, :pins, [%{id: 1, sort_order: 0}])
      assert Nav.rendered_tree(pinned) == first
      assert Nav.build_count() == before + 4
      assert Nav.rendered_tree(pinned) == first
      assert Nav.build_count() == before + 4
    end
  end

  describe "on_mount/4" do
    test "assigns the tree and keeps that same list while the scope is unchanged" do
      install!([Item.new!(%{id: "open", label: "Open", route: @served})])
      scope = scope([])

      before = Nav.build_count()

      assert {:cont, socket} =
               Nav.on_mount(:prepare, %{}, %{}, nav_socket(%{current_scope: scope}))

      assert Nav.build_count() == before + 1
      assert socket.assigns.nav == Nav.rendered_tree(scope)
      assert Nav.build_count() == before + 1

      assert Nav.refresh(socket).assigns.nav == socket.assigns.nav
      assert Nav.build_count() == before + 1
    end

    test "does not build a tree for a framed page" do
      before = Nav.build_count()

      assert {:cont, socket} =
               Nav.on_mount(:prepare, %{}, %{}, nav_socket(%{current_scope: %{framed: true}}))

      assert Nav.build_count() == before
      refute Map.has_key?(socket.assigns, :nav)
    end
  end

  defp nav_socket(assigns) do
    %Socket{
      router: __MODULE__,
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{lifecycle: %Lifecycle{}, live_temp: %{}}
    }
  end
end
