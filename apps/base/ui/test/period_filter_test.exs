defmodule Bilimbi.Base.UI.PeriodFilterTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Base.UI.PeriodFilter

  test "rolling presets include today and exactly the named number of days" do
    today = ~D[2026-10-11]

    for {period, days} <- [
          {"today", 1},
          {"last_7_days", 7},
          {"last_30_days", 30},
          {"last_90_days", 90}
        ] do
      state = PeriodFilter.parse(%{"period" => period}, today)
      assert state.to == today
      assert Date.diff(state.to, state.from) + 1 == days
      assert PeriodFilter.parse(PeriodFilter.params(state), today) == state
    end
  end

  test "this month includes its last day even in a leap year" do
    state = PeriodFilter.parse(%{"period" => "this_month"}, ~D[2028-02-12])
    assert state.from == ~D[2028-02-01]
    assert state.to == ~D[2028-02-29]
    assert {:ok, ~U[2028-02-01 00:00:00Z], ~U[2028-03-01 00:00:00Z]} = PeriodFilter.bounds(state)
  end

  test "custom validation refuses invalid and inverted ranges and accepts one day" do
    assert {:error, "Choose a valid start and end date."} =
             PeriodFilter.custom("2026-02-30", "2026-03-02")

    assert {:error, "Start date must be on or before end date."} =
             PeriodFilter.custom("2026-03-03", "2026-03-02")

    assert {:ok, state} = PeriodFilter.custom("2026-03-02", "2026-03-02")
    assert {:ok, ~U[2026-03-02 00:00:00Z], ~U[2026-03-03 00:00:00Z]} = PeriodFilter.bounds(state)
  end

  test "unknown presets and malformed URL dates fall back to the last 30 days" do
    today = ~D[2026-10-11]
    assert PeriodFilter.parse(%{"period" => "unknown"}, today) == PeriodFilter.parse(%{}, today)
    custom = PeriodFilter.parse(%{"period" => "custom", "from" => "invalid"}, today)
    assert custom.from == ~D[2026-09-12]
    assert custom.to == today
  end
end
