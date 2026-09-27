defmodule Bilimbi.Base.Grid.QueryTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Result
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @specs ~w(id label amount status customer.name customer.country.name lines:count lines.qty:sum
            lines.price:avg lines.price:max lines.sku:latest lines.sku:list tags.name:list
            customer.orders:count)

  setup do
    AuthzFixtures.create_authz_tables!()
    TestFixtures.install_test_registry!()
    TestFixtures.create_grid_tables!()
    TestFixtures.seed!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    catalog = Grid.catalog(TestFixtures.user_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(catalog, "orders")
    {:ok, columns} = Grid.resolve(catalog, orders, @specs)
    %{catalog: catalog, orders: orders, columns: columns}
  end

  defp cells(%Result{rows: rows}, key), do: Enum.find(rows, &(&1.key == key)).cells

  test "one statement walks one-links and rolls up many-links without multiplying rows", ctx do
    result = Grid.query(ctx.catalog, ctx.orders, ctx.columns)

    assert result.total_entries == 3
    assert Enum.map(result.rows, & &1.key) == [101, 102, 103]

    a = cells(result, 101)
    assert a["label"] == "Order A"
    assert a["customer-name"] == "Alpha Trading"
    assert a["customer-country-name"] == "Malaysia"
    assert a["lines_count"] == 3
    assert a["lines-qty_sum"] == 6
    assert Decimal.equal?(a["lines-price_avg"], Decimal.new("23.3333333333333333"))
    assert Decimal.equal?(a["lines-price_max"], Decimal.new("40.00"))
    assert a["lines-sku_latest"] == "SKU-3"
    assert a["lines-sku_list"] == "SKU-1, SKU-2, SKU-3"
    assert a["tags-name_list"] == "gift, rush"
    assert a["customer-orders_count"] == 1

    b = cells(result, 102)
    assert b["customer-country-name"] == "Singapore"
    assert b["lines_count"] == 1
    assert b["tags-name_list"] == "rush"

    # Order C's customer belongs to another tenant: the link respects the
    # target's own scope and comes back empty rather than leaking the name.
    c = cells(result, 103)
    assert c["customer-name"] == nil
    assert c["customer-country-name"] == nil
    assert c["lines_count"] == 0
    assert c["tags-name_list"] == nil
  end

  test "the other tenant sees only its own rows through the same catalog vocabulary", ctx do
    other = Grid.catalog(TestFixtures.other_tenant_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(other, "orders")
    {:ok, columns} = Grid.resolve(other, orders, ~w(label customer.name lines:count))
    result = Grid.query(other, orders, columns)

    assert result.total_entries == 1
    assert [%{key: 201, cells: cells}] = result.rows
    assert cells["customer-name"] == "Gamma Other Tenant"
    assert cells["lines_count"] == 1
  end

  test "a window is paged and sorted, by a rollup as much as by a field", ctx do
    {:ok, [count | _] = columns} = Grid.resolve(ctx.catalog, ctx.orders, ~w(lines:count label))

    result =
      Grid.query(ctx.catalog, ctx.orders, columns, sort: {count, :desc}, limit: 2, offset: 0)

    assert Enum.map(result.rows, & &1.key) == [101, 102]
    assert result.total_entries == 3
    assert Result.page(result) == %{page: 1, page_size: 2, total_entries: 3, total_pages: 2}

    result =
      Grid.query(ctx.catalog, ctx.orders, columns, sort: {count, :desc}, limit: 2, offset: 2)

    assert Enum.map(result.rows, & &1.key) == [103]
    assert Result.page(result).page == 2

    result = Grid.query(ctx.catalog, ctx.orders, columns, sort: {count, :asc})
    assert Enum.map(result.rows, & &1.key) == [103, 102, 101]
  end

  test "search matches the root's searchable text fields, escaping wildcards", ctx do
    {:ok, columns} = Grid.resolve(ctx.catalog, ctx.orders, ~w(label))

    result = Grid.query(ctx.catalog, ctx.orders, columns, search: "order b")
    assert Enum.map(result.rows, & &1.key) == [102]
    assert result.total_entries == 1

    assert Grid.query(ctx.catalog, ctx.orders, columns, search: "%").total_entries == 0
    assert Grid.query(ctx.catalog, ctx.orders, columns, search: "paid").total_entries == 1
  end

  test "stats span the whole set, and the planner's cost is reported", ctx do
    result = Grid.query(ctx.catalog, ctx.orders, ctx.columns, limit: 1)

    assert result.stats["lines_count"] == %{min: 0, max: 3}
    assert result.stats["id"] == %{min: 101, max: 103}
    assert Decimal.equal?(result.stats["amount"].max, Decimal.new("250.50"))
    refute Map.has_key?(result.stats, "label")
    refute Map.has_key?(result.stats, "lines-sku_list")
    assert is_float(result.cost) and result.cost > 0

    quiet = Grid.query(ctx.catalog, ctx.orders, ctx.columns, stats: false, cost: false)
    assert quiet.stats == %{} and quiet.cost == nil
  end

  test "attach fetches walked columns for rows a page already has", ctx do
    {:ok, columns} = Grid.resolve(ctx.catalog, ctx.orders, ~w(customer.country.name lines:count))
    values = Grid.attach(ctx.catalog, ctx.orders, [102, 101, 999], columns)

    assert values == %{
             101 => %{"customer-country-name" => "Malaysia", "lines_count" => 3},
             102 => %{"customer-country-name" => "Singapore", "lines_count" => 1}
           }

    assert Grid.attach(ctx.catalog, ctx.orders, [], columns) == %{}
  end

  test "expand lists the rows a rollup cell collapsed, newest first", ctx do
    {:ok, [lines, tags, deep]} =
      Grid.resolve(ctx.catalog, ctx.orders, ~w(lines:count tags.name:list customer.orders:count))

    assert {:ok, rows} = Grid.expand(ctx.catalog, ctx.orders, 101, lines)
    assert Enum.map(rows, & &1["sku"]) == ["SKU-3", "SKU-2", "SKU-1"]
    assert Enum.map(rows, &Map.keys(&1)) |> hd() |> Enum.sort() == ~w(created_at id price qty sku)

    assert {:ok, rows} = Grid.expand(ctx.catalog, ctx.orders, 101, tags)
    assert Enum.map(rows, & &1["name"]) == ["rush", "gift"]

    assert {:ok, rows} = Grid.expand(ctx.catalog, ctx.orders, 102, deep)
    assert Enum.map(rows, & &1["label"]) == ["Order B"]

    assert {:ok, []} = Grid.expand(ctx.catalog, ctx.orders, 103, lines)

    {:ok, [label]} = Grid.resolve(ctx.catalog, ctx.orders, ~w(label))
    assert {:error, :not_a_rollup} = Grid.expand(ctx.catalog, ctx.orders, 101, label)
  end

  test "a string-keyed root works the same way", ctx do
    {:ok, countries} = Grid.fetch_table(ctx.catalog, "countries")
    {:ok, columns} = Grid.resolve(ctx.catalog, countries, ~w(name population))
    result = Grid.query(ctx.catalog, countries, columns, sort: {hd(columns), :asc})

    assert Enum.map(result.rows, & &1.key) == ["MY", "SG"]
    assert result.stats["population"] == %{min: 6_000_000, max: 34_000_000}
  end
end
