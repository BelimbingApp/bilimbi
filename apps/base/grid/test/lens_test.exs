defmodule Bilimbi.Base.Grid.LensTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.Column
  alias Bilimbi.Base.Grid.ContributionValidator
  alias Bilimbi.Base.Grid.Lens
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources

  setup_all do
    %{tables: tables} =
      ContributionValidator.validate_contributions!([
        %{descriptor: TestFixtures.descriptor(), payload: TestSources.tables()}
      ])

    orders = tables["orders"]

    resolve = fn spec ->
      {:ok, column} = Column.resolve(spec, orders, &Map.fetch(tables, &1))
      column
    end

    %{resolve: resolve}
  end

  test "which lenses a column offers follows its shape", %{resolve: resolve} do
    assert Lens.available(resolve.("lines:count")) == [:value, :bar, :band, :trend, :delta]
    assert Lens.available(resolve.("lines.qty:sum")) == [:value, :bar, :band, :trend, :delta]
    assert Lens.available(resolve.("lines.price:avg")) == [:value, :bar, :band]
    assert Lens.available(resolve.("tags:count")) == [:value, :bar, :band]
    assert Lens.available(resolve.("placed_at")) == [:value, :bar, :band]
    assert Lens.available(resolve.("amount")) == [:value, :bar, :band]
    assert Lens.available(resolve.("label")) == [:value, :band]
    assert Lens.available(resolve.("lines.sku:list")) == [:value, :band]
    assert Lens.normalize("trend", resolve.("label")) == :value
    assert Lens.normalize("delta", resolve.("lines:count")) == :delta
  end

  test "a delta lens states the change, a trend lens carries its series", %{resolve: resolve} do
    count = resolve.("lines:count")
    stats = %{min: 0, max: 4}

    cell = Lens.cell(3, count, stats, :delta, %{before: 1})
    assert cell.text == "3 (+2)" and cell.delta == 2 and cell.series == nil
    assert Lens.cell(3, count, stats, :delta, %{before: 3}).text == "3 (±0)"
    assert Lens.cell(1, count, stats, :delta, %{before: 4}).text == "1 (−3)"
    assert Lens.cell(2, count, stats, :delta, %{}).text == "2 (+2)"
    assert Lens.cell(nil, count, stats, :delta, %{before: 1}).text == ""

    trend = Lens.cell(3, count, stats, :trend, %{series: [0.0, 1.0, 2.0]})
    assert trend.series == [0.0, 1.0, 2.0] and trend.text == "3" and trend.delta == nil
    assert Lens.cell(3, count, stats, :value, %{series: [1.0]}).series == nil
    assert Lens.normalize("delta", resolve.("placed_at")) == :value
  end
end
