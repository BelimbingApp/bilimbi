defmodule Bilimbi.Base.Grid.CatalogTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Catalog
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  setup do
    AuthzFixtures.create_authz_tables!()
    TestFixtures.install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "a catalog holds only the tables the actor's capabilities read" do
    scope = TestFixtures.user_scope(~w(admin.test.order.view admin.test.customer.view))
    catalog = Grid.catalog(scope)

    assert Enum.map(Grid.tables(catalog), & &1.id) == ~w(customers metrics orders)
    assert {:ok, _} = Grid.fetch_table(catalog, "orders")
    assert :error = Grid.fetch_table(catalog, "countries")
  end

  test "a system scope names nobody and reads nothing" do
    assert Grid.tables(Grid.catalog(TestFixtures.system_scope(1))) == []
  end

  test "a path through an unreadable table is refused even when the root is readable" do
    scope = TestFixtures.user_scope(~w(admin.test.order.view admin.test.customer.view))
    catalog = Grid.catalog(scope)
    {:ok, orders} = Grid.fetch_table(catalog, "orders")

    assert {:error, {"customer.country.name", {:forbidden_table, "countries"}}} =
             Grid.resolve(catalog, orders, ["label", "customer.country.name"])

    assert {:error, {"lines:count", {:forbidden_table, "lines"}}} =
             Grid.resolve(catalog, orders, ["lines:count"])

    assert {:ok, [_label, _customer]} = Grid.resolve(catalog, orders, ["label", "customer.name"])
  end

  test "default columns are the root's visible fields" do
    catalog = Grid.catalog(TestFixtures.user_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(catalog, "orders")

    assert Enum.map(Grid.default_columns(catalog, orders), & &1.spec) ==
             ~w(id label amount status placed_at)
  end

  test "suggestions walk visible links up to three deep and rank the typed words" do
    catalog = Grid.catalog(TestFixtures.user_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(catalog, "orders")

    specs = Grid.suggest(catalog, orders, "", limit: 100) |> Enum.map(& &1.spec)

    assert "label" in specs
    assert "customer.name" in specs
    assert "customer.country.name" in specs
    assert "customer.country.population" in specs
    assert "lines:count" in specs
    assert "lines.qty:sum" in specs
    assert "lines.created_at:max" in specs
    assert "lines.sku:list" in specs
    assert "lines.sku:latest" in specs
    assert "tags.name:list" in specs
    refute "tags.name:latest" in specs
    refute "customer_id" in specs

    [first | _rest] = Grid.suggest(catalog, orders, "country name")
    assert first.spec == "customer.country.name"

    [first | _rest] = Grid.suggest(catalog, orders, "lines count")
    assert first.spec == "lines:count"

    assert Grid.suggest(catalog, orders, "zebra") == []

    assert Grid.suggest(catalog, orders, "", exclude: ["label"], limit: 100)
           |> Enum.map(& &1.spec)
           |> Enum.member?("label") == false
  end

  test "suggestions never cross an unreadable table" do
    catalog =
      Grid.catalog(TestFixtures.user_scope(~w(admin.test.order.view admin.test.customer.view)))

    {:ok, orders} = Grid.fetch_table(catalog, "orders")
    specs = Grid.suggest(catalog, orders, "", limit: 100) |> Enum.map(& &1.spec)

    assert "customer.name" in specs
    refute Enum.any?(specs, &String.starts_with?(&1, "customer.country"))
    refute Enum.any?(specs, &String.starts_with?(&1, "lines"))
  end

  test "the catalog module itself exposes the installed vocabulary" do
    assert %{tables: tables} = Catalog.installed()
    assert Map.keys(tables) |> length() == 6
  end
end
