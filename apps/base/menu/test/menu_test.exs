defmodule Bilimbi.Base.MenuTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Menu
  alias Bilimbi.Base.Menu.ContributionValidator, as: Validator
  alias Bilimbi.Base.Menu.Item
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  defp entry(owner, items), do: %{descriptor: %{id: owner}, payload: items}

  defp install!(items) do
    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "test",
      consumers: %{menu: items}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  describe "validation" do
    test "orders deterministically by order then id, not by contribution order" do
      items =
        Validator.validate_contributions!([
          entry("core/user", [%{id: "admin.user", label: "Users", route: "/users", order: 20}]),
          entry("core/company", [
            %{id: "admin.company", label: "Companies", route: "/companies", order: 10}
          ])
        ])

      assert Enum.map(items, & &1.id) == ["admin.company", "admin.user"]
    end

    test "retains the contributing module descriptor id as source" do
      items =
        Validator.validate_contributions!([
          entry("core/user", [%{id: "admin.user", label: "Users", route: "/users"}]),
          entry("core/company", [%{id: "admin.company", label: "Companies", route: "/companies"}])
        ])

      assert [
               %Item{id: "admin.company", source: "core/company"},
               %Item{id: "admin.user", source: "core/user"}
             ] = items
    end

    test "a contribution cannot name a source other than its own module" do
      items =
        Validator.validate_contributions!([
          entry("base/system", [
            %{id: "admin.spoof", label: "Spoof", route: "/spoof", source: "core/user"}
          ])
        ])

      assert [%Item{id: "admin.spoof", source: "base/system"}] = items
    end

    test "resolves a parent contributed by a different module" do
      items =
        Validator.validate_contributions!([
          entry("core/employee", [
            %{id: "admin.employee", label: "Employees", parent: "admin", route: "/e"}
          ]),
          entry("base/menu", [%{id: "admin", label: "Administration"}])
        ])

      assert Enum.map(items, & &1.id) |> Enum.sort() == ["admin", "admin.employee"]
    end

    test "drops an item whose parent is missing instead of raising" do
      items =
        Validator.validate_contributions!([
          entry("core/ai", [%{id: "admin.ai", label: "AI", parent: "nowhere", route: "/ai"}]),
          entry("base/menu", [%{id: "admin", label: "Administration"}])
        ])

      assert Enum.map(items, & &1.id) == ["admin"]
    end

    test "raises on duplicate ids and names both contributors" do
      assert_raise ArgumentError, ~r/duplicate menu item ids.*core\/a.*core\/b/s, fn ->
        Validator.validate_contributions!([
          entry("core/a", [%{id: "admin.dup", label: "A"}]),
          entry("core/b", [%{id: "admin.dup", label: "B"}])
        ])
      end
    end

    test "raises on a circular parent chain" do
      assert_raise ArgumentError, ~r/circular menu parent reference/, fn ->
        Validator.validate_contributions!([
          entry("core/a", [
            %{id: "one", label: "One", parent: "two"},
            %{id: "two", label: "Two", parent: "one"}
          ])
        ])
      end
    end

    test "rejects a malformed item" do
      assert_raise ArgumentError, ~r/needs a non-empty label/, fn ->
        Validator.validate_contributions!([entry("core/a", [%{id: "ok", label: ""}])])
      end

      assert_raise ArgumentError, ~r/menu item id is invalid/, fn ->
        Validator.validate_contributions!([entry("core/a", [%{id: "Bad Id", label: "x"}])])
      end
    end
  end

  describe "visible_tree/1" do
    setup do
      install!([
        Item.new!(%{id: "admin", label: "Administration"}),
        Item.new!(%{
          id: "admin.company",
          label: "Companies",
          parent: "admin",
          route: "/companies",
          capability: "admin.company.list"
        }),
        Item.new!(%{
          id: "admin.user",
          label: "Users",
          parent: "admin",
          route: "/users",
          capability: "admin.user.list"
        }),
        Item.new!(%{id: "production", label: "Production"})
      ])
    end

    test "hides items whose capability the actor lacks" do
      tree = Menu.visible_tree(&(&1 == "admin.company.list"))

      assert [%{item: %Item{id: "admin"}, children: [%{item: %Item{id: "admin.company"}}]}] = tree
    end

    test "hides a container that has no visible child" do
      # "production" is a route-less root with no children, exactly like an
      # unported Domain: it must not render as an empty heading.
      tree = Menu.visible_tree(fn _ -> true end)

      refute Enum.any?(tree, &(&1.item.id == "production"))
    end

    test "hides the parent entirely when every child is denied" do
      assert Menu.visible_tree(fn _ -> false end) == []
    end

    test "an item without a capability is always visible" do
      install!([Item.new!(%{id: "dash", label: "Dashboard", route: "/dashboard"})])

      assert [%{item: %Item{id: "dash"}}] = Menu.visible_tree(fn _ -> false end)
    end
  end

  test "fetch_item/1" do
    install!([Item.new!(%{id: "admin", label: "Administration"})])

    assert {:ok, %Item{id: "admin"}} = Menu.fetch_item("admin")
    assert :error = Menu.fetch_item("missing")
  end
end
