defmodule Bilimbi.Base.Grid.Web.HostTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.Result
  alias Bilimbi.Base.Grid.Web.Host

  defp result(cost),
    do: %Result{columns: [], rows: [], total_entries: 0, offset: 0, limit: 0, cost: cost}

  test "a result the planner did not cost carries no cost" do
    assert Host.cost(result(nil)) == nil
  end

  test "a cost is heavy only above the threshold" do
    heavy = Host.heavy_cost()

    assert Host.cost(result(heavy)) == %{estimate: heavy, heavy?: false}
    assert Host.cost(result(heavy + 1.0)) == %{estimate: heavy + 1.0, heavy?: true}
  end
end
