defmodule Bilimbi.Base.Grid.QueryTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Grid
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

  test "one statement walks one-links and rolls up many-links without multiplying rows", ctx do
    rows = Grid.attach(ctx.catalog, ctx.orders, [101, 102, 103], ctx.columns)

    assert rows |> Map.keys() |> Enum.sort() == [101, 102, 103]

    a = rows[101].cells
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

    b = rows[102].cells
    assert b["customer-country-name"] == "Singapore"
    assert b["lines_count"] == 1
    assert b["tags-name_list"] == "rush"

    # Order C's customer belongs to another tenant: the link respects the
    # target's own scope and comes back empty rather than leaking the name.
    c = rows[103].cells
    assert c["customer-name"] == nil
    assert c["customer-country-name"] == nil
    assert c["lines_count"] == 0
    assert c["tags-name_list"] == nil
  end

  test "the other tenant sees only its own rows through the same catalog vocabulary", _ctx do
    other = Grid.catalog(TestFixtures.other_tenant_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(other, "orders")
    {:ok, columns} = Grid.resolve(other, orders, ~w(label customer.name lines:count))

    # Asked for every order by key, the other tenant's scope reaches only its own.
    rows = Grid.attach(other, orders, [101, 102, 103, 201], columns)

    assert Map.keys(rows) == [201]
    assert rows[201].cells["customer-name"] == "Gamma Other Tenant"
    assert rows[201].cells["lines_count"] == 1
  end

  test "stats span every root row, and the planner's cost of reading them is reported", ctx do
    {stats, cost} = Grid.stats(ctx.catalog, ctx.orders, ctx.columns)

    assert stats["lines_count"] == %{min: 0, max: 3}
    assert stats["id"] == %{min: 101, max: 103}
    assert Decimal.equal?(stats["amount"].max, Decimal.new("250.50"))
    refute Map.has_key?(stats, "label")
    refute Map.has_key?(stats, "lines-sku_list")
    assert is_float(cost) and cost > 0

    # Nothing numeric to scale: no statement, so no cost.
    {:ok, text} = Grid.resolve(ctx.catalog, ctx.orders, ~w(label lines.sku:list))
    assert Grid.stats(ctx.catalog, ctx.orders, text) == {%{}, nil}
  end

  test "attach fetches walked columns for rows a page already has", ctx do
    {:ok, columns} = Grid.resolve(ctx.catalog, ctx.orders, ~w(customer.country.name lines:count))
    values = Grid.attach(ctx.catalog, ctx.orders, [102, 101, 999], columns)

    assert values == %{
             101 => %{
               cells: %{"customer-country-name" => "Malaysia", "lines_count" => 3},
               series: %{},
               before: %{}
             },
             102 => %{
               cells: %{"customer-country-name" => "Singapore", "lines_count" => 1},
               series: %{},
               before: %{}
             }
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
    rows = Grid.attach(ctx.catalog, countries, ["SG", "MY"], columns)

    assert rows |> Map.keys() |> Enum.sort() == ["MY", "SG"]
    assert rows["MY"].cells["name"] == "Malaysia"

    assert {%{"population" => %{min: 6_000_000, max: 34_000_000}}, _cost} =
             Grid.stats(ctx.catalog, countries, columns)
  end

  test "a trend is the rollup per calendar month over the last twelve, a delta the rollup as of a date",
       ctx do
    {:ok, [count, total] = columns} =
      Grid.resolve(ctx.catalog, ctx.orders, ~w(lines:count lines.qty:sum))

    months = Bilimbi.Base.Grid.Query.trend_months()
    assert length(months) == 12

    rows =
      Grid.attach(ctx.catalog, ctx.orders, [101, 102, 103], columns,
        trend: [count, total],
        delta: {[count, total], ~N[2026-02-01 00:00:00]}
      )

    a = rows[101]
    b = rows[102]
    c = rows[103]

    # Order A's three lines are all in January 2026; order B's one in February.
    at = fn series, {year, month} ->
      Enum.at(series, Enum.find_index(months, &(&1 == {year, month})))
    end

    assert at.(a.series["lines_count"], {2026, 1}) == 3.0
    assert at.(a.series["lines-qty_sum"], {2026, 1}) == 6.0
    assert Enum.sum(a.series["lines_count"]) == 3.0
    assert at.(b.series["lines_count"], {2026, 2}) == 1.0
    assert Enum.sum(b.series["lines_count"]) == 1.0
    assert c.series["lines_count"] == List.duplicate(0.0, 12)

    # As of 1 February, order A already had its lines and order B had none.
    assert a.before["lines_count"] == 3 and a.before["lines-qty_sum"] == 6
    assert b.before["lines_count"] == 0 and b.before["lines-qty_sum"] == nil
    assert c.before["lines_count"] == 0

    # Neither is asked for: the plain shape stays.
    plain = Grid.attach(ctx.catalog, ctx.orders, [101], columns)
    assert plain[101].series == %{} and plain[101].before == %{}
  end
end
