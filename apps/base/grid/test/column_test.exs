defmodule Bilimbi.Base.Grid.ColumnTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.ContributionValidator
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources

  setup_all do
    %{tables: tables} =
      ContributionValidator.validate_contributions!([
        %{descriptor: TestFixtures.descriptor(), payload: TestSources.tables()}
      ])

    %{tables: tables, orders: tables["orders"], fetch: &Map.fetch(tables, &1)}
  end

  test "a root field", %{orders: orders, fetch: fetch} do
    assert {:ok, %Column{kind: :field, type: :decimal, hops: [], label: "Amount", id: "amount"}} =
             Column.resolve("amount", orders, fetch)
  end

  test "a field reached through one-links", %{orders: orders, fetch: fetch} do
    assert {:ok, column} = Column.resolve("customer.country.name", orders, fetch)
    assert column.kind == :field
    assert Enum.map(column.hops, & &1.id) == ~w(customer country)
    assert column.table.id == "countries"
    assert column.label == "Customer › Country › Name"
    assert column.id == "customer-country-name"
    assert column.depth == 2
  end

  test "rollups through a many-link", %{orders: orders, fetch: fetch} do
    assert {:ok,
            %Column{
              kind: :rollup,
              agg: :count,
              type: :integer,
              field: nil,
              label: "Lines › Count"
            }} =
             Column.resolve("lines:count", orders, fetch)

    assert {:ok, %Column{agg: :sum, type: :integer, label: "Lines › Quantity (Sum)"}} =
             Column.resolve("lines.qty:sum", orders, fetch)

    assert {:ok, %Column{agg: :avg, type: :float}} =
             Column.resolve("lines.price:avg", orders, fetch)

    assert {:ok, %Column{agg: :max, type: :datetime}} =
             Column.resolve("lines.created_at:max", orders, fetch)

    assert {:ok, %Column{agg: :latest, type: :string}} =
             Column.resolve("lines.sku:latest", orders, fetch)

    assert {:ok, %Column{agg: :list, type: :string}} =
             Column.resolve("tags.name:list", orders, fetch)
  end

  test "one-links may follow the many-link inside the rollup", %{orders: orders, fetch: fetch} do
    assert {:ok, column} = Column.resolve("customer.orders.amount:sum", orders, fetch)
    assert Enum.map(column.hops, & &1.id) == ["customer"]
    assert column.many.id == "orders"
    assert column.tail == []
    assert column.type == :decimal

    assert {:error, {:second_many_link, "lines"}} =
             Column.resolve("customer.orders.lines:count", orders, fetch)

    assert {:ok, column} = Column.resolve("lines.order.customer.name:list", orders, fetch)
    assert column.many.id == "lines"
    assert Enum.map(column.tail, & &1.id) == ~w(order customer)
    assert column.table.id == "customers"
  end

  test "malformed and impossible paths are refused by name", %{orders: orders, fetch: fetch} do
    assert {:error, {:malformed, "Amount"}} = Column.resolve("Amount", orders, fetch)
    assert {:error, {:malformed, "amount;drop"}} = Column.resolve("amount;drop", orders, fetch)
    assert {:error, {:unknown_segment, "nope", "orders"}} = Column.resolve("nope", orders, fetch)

    assert {:error, {:unknown_segment, "customer_id", "orders"}} =
             Column.resolve("customer_id", orders, fetch)

    assert {:error, {:unknown_segment, "customer", "customers"}} =
             Column.resolve("customer.customer", orders, fetch)

    assert {:error, {:no_field, "customer"}} = Column.resolve("customer", orders, fetch)

    assert {:error, {:many_link_needs_aggregate, "lines"}} =
             Column.resolve("lines", orders, fetch)

    assert {:error, {:many_link_needs_aggregate, "lines.qty"}} =
             Column.resolve("lines.qty", orders, fetch)

    assert {:error, {:aggregate_without_many_link, "amount:sum"}} =
             Column.resolve("amount:sum", orders, fetch)

    assert {:error, {:count_takes_no_field, "lines.qty:count"}} =
             Column.resolve("lines.qty:count", orders, fetch)

    assert {:error, {:aggregate_needs_field, "lines:sum"}} =
             Column.resolve("lines:sum", orders, fetch)

    assert {:error, {:aggregate_needs_number, "lines.sku:sum"}} =
             Column.resolve("lines.sku:sum", orders, fetch)

    assert {:error, {:second_many_link, "orders"}} =
             Column.resolve("lines.order.customer.orders:count", orders, fetch)

    assert {:error, {:latest_needs_time_field, "tags.name:latest"}} =
             Column.resolve("tags.name:latest", orders, fetch)
  end

  test "a path through a table the catalog left out is refused as forbidden", %{
    orders: orders,
    tables: tables
  } do
    without_countries = &Map.fetch(Map.delete(tables, "countries"), &1)

    assert {:error, {:forbidden_table, "countries"}} =
             Column.resolve("customer.country.name", orders, without_countries)

    assert {:ok, _column} = Column.resolve("customer.name", orders, without_countries)
  end
end
