defmodule Bilimbi.Base.Grid.PerformanceTest do
  @moduledoc """
  Timings over a synthetic set, measured as a list page runs them: walked
  columns and rollups attached to one page of rows the page already has,
  the range of the numeric ones over every root row (what a bar or a band
  scales to), and one rollup expanded. Excluded by default; run with
  `mix test --include performance`.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  @moduletag :performance
  @moduletag timeout: 600_000

  @orders 20_000
  @customers 500
  @lines_per_order 4

  setup do
    AuthzFixtures.create_authz_tables!()
    TestFixtures.install_test_registry!()
    TestFixtures.create_grid_tables!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    TestFixtures.insert_country!("MY", "Malaysia", 34_000_000)
    TestFixtures.insert_country!("SG", "Singapore", 6_000_000)

    SQL.query!(
      Repo,
      """
      INSERT INTO grid_test_customers (id, tenant_id, name, country_code)
      SELECT n, 1, 'Customer ' || n, CASE WHEN n % 2 = 0 THEN 'MY' ELSE 'SG' END FROM generate_series(1, $1) n
      """,
      [@customers]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO grid_test_orders (id, tenant_id, label, amount, status, placed_at, customer_id)
      SELECT n, 1, 'Order ' || n, (n % 1000)::numeric, (ARRAY['open','paid','void'])[(n % 3) + 1],
             timestamp '2026-01-01' + (n % 365) * interval '1 day', (n % $2) + 1
      FROM generate_series(1, $1) n
      """,
      [@orders, @customers]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO grid_test_lines (order_id, sku, qty, price, created_at)
      SELECT o, 'SKU-' || (o % 50), (o % 7) + 1, ((o % 90) + 10)::numeric, timestamp '2026-01-01' + (o % 300) * interval '1 hour'
      FROM generate_series(1, $1) o, generate_series(1, $2) l
      """,
      [@orders, @lines_per_order]
    )

    SQL.query!(
      Repo,
      "INSERT INTO grid_test_tags (id, name) VALUES (1, 'rush'), (2, 'gift'), (3, 'bulk')",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO grid_test_metrics (order_id, " <>
        Enum.map_join(1..60, ", ", &"m#{&1}") <>
        ") SELECT o, " <>
        Enum.map_join(1..60, ", ", &"(o * #{&1}) % 1000") <> " FROM generate_series(1, $1) o",
      [@orders]
    )

    SQL.query!(
      Repo,
      "INSERT INTO grid_test_order_tags (order_id, tag_id) SELECT o, (o % 3) + 1 FROM generate_series(1, $1) o",
      [@orders]
    )

    for table <-
          ~w(grid_test_orders grid_test_lines grid_test_customers grid_test_order_tags grid_test_metrics) do
      SQL.query!(Repo, "ANALYZE #{table}", [])
    end

    catalog = Grid.catalog(TestFixtures.user_scope(TestSources.capabilities()))
    {:ok, orders} = Grid.fetch_table(catalog, "orders")
    %{catalog: catalog, orders: orders}
  end

  # Every distinct column the catalog can offer from orders, walked specs
  # and rollups alike, so a hundred-column grid is a hundred different
  # statements' worth of work in one.
  defp specs(catalog, orders, count) do
    base =
      ~w(id label amount status placed_at customer.name customer.country.name customer.country.population
              lines:count lines.qty:sum lines.price:avg lines.price:max lines.sku:latest lines.sku:list tags.name:list
              customer.orders:count customer.orders.amount:sum customer.orders.amount:avg lines.created_at:max lines.qty:min)

    offered = catalog |> Grid.suggest(orders, "", limit: 1000) |> Enum.map(& &1.spec)
    (base ++ offered) |> Enum.uniq() |> Enum.take(count)
  end

  defp time(fun) do
    {micros, result} = :timer.tc(fun)
    {micros / 1000, result}
  end

  test "a page of rows with up to 100 walked and rolled-up columns, over 20,000 root rows", ctx do
    IO.puts(
      "\n=== grid performance: #{@orders} orders, #{@customers} customers, #{@orders * @lines_per_order} lines ==="
    )

    page = Enum.to_list(1..25)
    largest_page = Enum.to_list(1..300)

    for count <- [5, 20, 50, 100] do
      {:ok, columns} =
        Grid.resolve(ctx.catalog, ctx.orders, specs(ctx.catalog, ctx.orders, count))

      rollups = Enum.filter(columns, &(&1.kind == :rollup and &1.agg in [:count, :sum]))

      {page_ms, attached} = time(fn -> Grid.attach(ctx.catalog, ctx.orders, page, columns) end)

      {largest_ms, largest} =
        time(fn -> Grid.attach(ctx.catalog, ctx.orders, largest_page, columns) end)

      {lensed_ms, _} =
        time(fn ->
          Grid.attach(ctx.catalog, ctx.orders, page, columns,
            trend: Enum.take(rollups, 2),
            delta: {Enum.take(rollups, 2), ~N[2026-06-01 00:00:00]}
          )
        end)

      {stats_ms, {stats, cost}} = time(fn -> Grid.stats(ctx.catalog, ctx.orders, columns) end)

      IO.puts(
        "columns=#{length(columns)} | attach to a page of 25: #{Float.round(page_ms, 1)} ms | " <>
          "to a page of 300: #{Float.round(largest_ms, 1)} ms | " <>
          "25 with two trends and two changes: #{Float.round(lensed_ms, 1)} ms | " <>
          "range of #{map_size(stats)} numeric columns over #{@orders} rows: " <>
          "#{Float.round(stats_ms, 1)} ms (cost #{trunc(cost || 0)})"
      )

      assert map_size(attached) == 25
      assert map_size(largest) == 300
    end

    {:ok, [count_column | _]} =
      Grid.resolve(ctx.catalog, ctx.orders, ~w(lines:count customer.country.name))

    {expand_ms, {:ok, rows}} =
      time(fn -> Grid.expand(ctx.catalog, ctx.orders, 17, count_column) end)

    IO.puts("expand one rollup: #{Float.round(expand_ms, 1)} ms (#{length(rows)} rows)")
    assert length(rows) == @lines_per_order
  end
end
