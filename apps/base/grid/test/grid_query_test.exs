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

  test "the other tenant sees only its own rows through the same catalog vocabulary", _ctx do
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
    result = Grid.query(ctx.catalog, countries, columns, sort: {hd(columns), :asc})

    assert Enum.map(result.rows, & &1.key) == ["MY", "SG"]
    assert result.stats["population"] == %{min: 6_000_000, max: 34_000_000}
  end

  test "a focus narrows the rows to one selected record, of the root or through a link", ctx do
    {:ok, columns} = Grid.resolve(ctx.catalog, ctx.orders, ~w(label customer.name))

    assert {:ok, :root, %{id: "id", type: :integer}, "test/order"} =
             Grid.focus_column(ctx.catalog, ctx.orders, "self")

    result = Grid.query(ctx.catalog, ctx.orders, columns, focus: {:root, 102})
    assert Enum.map(result.rows, & &1.key) == [102]
    assert result.total_entries == 1

    assert {:ok, %Bilimbi.Base.Grid.Column{spec: "customer.id"}, %{id: "id"}, "test/customer"} =
             Grid.focus_column(ctx.catalog, ctx.orders, "customer")

    {:ok, via, _field, _kind} = Grid.focus_column(ctx.catalog, ctx.orders, "customer")
    result = Grid.query(ctx.catalog, ctx.orders, columns, focus: {via, 1})
    assert Enum.map(result.rows, & &1.key) == [101]
    assert result.total_entries == 1

    # The focus column is joined for the filter, never shown.
    assert Map.keys(hd(result.rows).cells) |> Enum.sort() == ["customer-name", "label"]

    assert :error = Grid.focus_column(ctx.catalog, ctx.orders, "lines")
    assert :error = Grid.focus_column(ctx.catalog, ctx.orders, "nope")

    {:ok, countries} = Grid.fetch_table(ctx.catalog, "countries")
    assert :error = Grid.focus_column(ctx.catalog, countries, "self")

    assert Enum.map(Grid.follow_options(ctx.catalog, ctx.orders), & &1.follow) == [
             "self",
             "customer"
           ]

    assert Enum.map(Grid.follow_options(ctx.catalog, ctx.orders), & &1.kind) == [
             "test/order",
             "test/customer"
           ]
  end

  test "a trend is the rollup per calendar month over the last twelve, a delta the rollup as of a date",
       ctx do
    {:ok, [count, total] = columns} =
      Grid.resolve(ctx.catalog, ctx.orders, ~w(lines:count lines.qty:sum))

    months = Bilimbi.Base.Grid.Query.trend_months()
    assert length(months) == 12

    result =
      Grid.query(ctx.catalog, ctx.orders, columns,
        trend: [count, total],
        delta: {[count, total], ~N[2026-02-01 00:00:00]}
      )

    a = Enum.find(result.rows, &(&1.key == 101))
    b = Enum.find(result.rows, &(&1.key == 102))
    c = Enum.find(result.rows, &(&1.key == 103))

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
    plain = Grid.query(ctx.catalog, ctx.orders, columns)
    assert hd(plain.rows).series == %{} and hd(plain.rows).before == %{}

    # A window through attach carries them too.
    attached =
      Grid.attach(ctx.catalog, ctx.orders, [102], columns,
        trend: [count],
        delta: {[count], ~N[2026-03-01 00:00:00]}
      )

    assert attached[102].before["lines_count"] == 1
    assert Enum.sum(attached[102].series["lines_count"]) == 1.0
  end

  test "a pivot counts root rows per pair of values in one statement, folding the long tail",
       ctx do
    {:ok, [status, country]} =
      Grid.resolve(ctx.catalog, ctx.orders, ~w(status customer.country.name))

    pivot = Grid.pivot(ctx.catalog, ctx.orders, status, country)

    assert Enum.map(pivot.columns, & &1.short_label) ==
             [status.short_label, "—", "Malaysia", "Singapore", "Total"]

    assert Enum.map(pivot.columns, & &1.id) == ["pv-rows", "pv-0", "pv-1", "pv-2", "pv-total"]
    assert Enum.map(pivot.rows, & &1.key) == ["open", "paid", "void"]

    paid = Enum.find(pivot.rows, &(&1.key == "paid"))

    assert paid.cells == %{
             "pv-rows" => "paid",
             "pv-0" => 0,
             "pv-1" => 1,
             "pv-2" => 0,
             "pv-total" => 1
           }

    void = Enum.find(pivot.rows, &(&1.key == "void"))
    # Order C's customer is in another tenant, so its country is unknown here.
    assert void.cells == %{
             "pv-rows" => "void",
             "pv-0" => 1,
             "pv-1" => 0,
             "pv-2" => 0,
             "pv-total" => 1
           }

    assert pivot.total_entries == 3 and pivot.more == false and is_float(pivot.cost)
    assert pivot.stats["pv-total"] == %{min: 0, max: 1}
    refute Map.has_key?(pivot.stats, "pv-rows")
    assert Enum.all?(pivot.rows, &(&1.cells["pv-rows"] == &1.key))

    narrowed = Grid.pivot(ctx.catalog, ctx.orders, status, country, search: "order b")
    assert Enum.map(narrowed.rows, & &1.key) == ["open"]
  end

  test "a pivot reads a bounded number of pairs and leaves out a row it could not finish",
       ctx do
    {:ok, [status, country]} =
      Grid.resolve(ctx.catalog, ctx.orders, ~w(status customer.country.name))

    all = Grid.pivot(ctx.catalog, ctx.orders, status, country)

    pairs =
      Enum.map(
        all.rows,
        &Enum.count(&1.cells, fn {id, n} -> id not in ["pv-rows", "pv-total"] and n > 0 end)
      )

    exact = Grid.pivot(ctx.catalog, ctx.orders, status, country, max_pairs: Enum.sum(pairs))
    assert exact.more == false and exact.rows == all.rows

    first = hd(pairs)
    bounded = Grid.pivot(ctx.catalog, ctx.orders, status, country, max_pairs: first + 1)
    assert bounded.more == true
    assert Enum.map(bounded.rows, & &1.key) == ["open"]
    assert hd(bounded.rows).cells["pv-total"] == hd(all.rows).cells["pv-total"]
  end

  test "a pivot bound inside its first row shows no row rather than a short one", ctx do
    {:ok, lines} = Grid.fetch_table(ctx.catalog, "lines")
    {:ok, [order, sku]} = Grid.resolve(ctx.catalog, lines, ~w(order.label sku))

    all = Grid.pivot(ctx.catalog, lines, order, sku)
    first = hd(all.rows)
    assert first.key == "Order A" and first.cells["pv-total"] >= 2

    cut = Grid.pivot(ctx.catalog, lines, order, sku, max_pairs: 1)
    assert cut.more == true and cut.rows == [] and cut.total_entries == 0
  end
end
