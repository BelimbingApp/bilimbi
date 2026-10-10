defmodule Bilimbi.Base.Grid.CatalogTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Catalog
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  setup do
    AuthzFixtures.create_authz_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    TestFixtures.install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "a catalog holds only the tables the actor's capabilities read" do
    scope = TestFixtures.user_scope(~w(admin.test.order.view admin.test.customer.view))
    catalog = Grid.catalog(scope)

    assert catalog.tables |> Map.keys() |> Enum.sort() == ~w(customers metrics orders)
    assert {:ok, _} = Grid.fetch_table(catalog, "orders")
    assert :error = Grid.fetch_table(catalog, "countries")
  end

  test "a field with no column is read from the source key its id names" do
    catalog = Grid.catalog(TestFixtures.user_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(catalog, "orders")

    assert orders.fields["placed_at"].column == :placed_at
    assert orders.fields["customer_id"].column == :customer_id
  end

  test "an explicit column wins over the field id" do
    install_orders!(fn fields -> fields ++ [%{id: "title", type: :string, column: :label}] end)

    catalog = Grid.catalog(TestFixtures.user_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(catalog, "orders")

    assert orders.fields["title"].column == :label
  end

  test "a field no source key answers to is refused when the catalog is built, naming the field" do
    install_orders!(fn fields -> fields ++ [%{id: "missing", type: :string}] end)
    scope = TestFixtures.user_scope(TestSources.capabilities())

    assert_raise ArgumentError,
                 ~r/invalid grid table from base\/grid \("orders"\): field missing names no key its source .*Orders selects; it selects \[:id, :label/,
                 fn -> Grid.catalog(scope) end

    # An account that may not read the table is not stopped by it.
    assert %Catalog{} =
             Grid.catalog(TestFixtures.other_tenant_scope(~w(admin.test.customer.view)))
  end

  defp install_orders!(change_fields) do
    %{tables: [orders | rest]} = TestSources.tables()

    TestFixtures.install_test_registry!(%{
      tables: [Map.update!(orders, :fields, change_fields) | rest]
    })
  end

  test "a system scope names nobody and reads nothing" do
    assert Grid.catalog(TestFixtures.system_scope(1)).tables == %{}
  end

  test "a field an operator restricted leaves the catalog of an account holding one of its roles" do
    # The restriction is tenant 1's, on orders.amount, for the Finance role.
    operator = TestFixtures.user_scope(~w(admin.authz.field.manage admin.test.order.view))
    {:ok, finance} = Authz.create_role(operator, 10, %{name: "Finance", code: "finance"})
    {:ok, _} = Authz.put_field_restriction(operator, "orders", "amount", [finance.id])

    # Visible by default: the account holds no restricted role.
    without = Grid.catalog(operator)
    {:ok, orders} = Grid.fetch_table(without, "orders")
    assert orders.field_order == ~w(id label amount status placed_at customer_id)
    assert {:ok, [_amount]} = Grid.resolve(without, orders, ["amount"])

    {:ok, :assigned} = Authz.assign_role(operator, 10, :user, 7, finance.id)
    holder = Grid.catalog(operator)
    {:ok, orders} = Grid.fetch_table(holder, "orders")
    refute Map.has_key?(orders.fields, "amount")
    assert orders.field_order == ~w(id label status placed_at customer_id)

    assert {:error, {"amount", {:unknown_segment, "amount", "orders"}}} =
             Grid.resolve(holder, orders, ["amount"])

    refute Enum.any?(Catalog.suggest(holder, orders, "amount"), &(&1.spec == "amount"))

    # Another tenant's catalog is untouched by tenant 1's restriction.
    other = Grid.catalog(TestFixtures.other_tenant_scope(~w(admin.test.order.view)))
    {:ok, orders} = Grid.fetch_table(other, "orders")
    assert Map.has_key?(orders.fields, "amount")
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
