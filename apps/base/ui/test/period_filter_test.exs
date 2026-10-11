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

  defmodule FakeDb do
    @behaviour Calendar.TimeZoneDatabase

    @std %{utc_offset: -18_000, std_offset: 0, zone_abbr: "ST"}
    @dst %{utc_offset: -18_000, std_offset: 3600, zone_abbr: "DT"}

    @impl true
    def time_zone_period_from_utc_iso_days(_iso_days, "Etc/UTC"),
      do: {:ok, %{utc_offset: 0, std_offset: 0, zone_abbr: "UTC"}}

    def time_zone_period_from_utc_iso_days(_iso_days, "Test/Gap"), do: {:ok, @std}
    def time_zone_period_from_utc_iso_days(_iso_days, "Test/Fold"), do: {:ok, @std}
    def time_zone_period_from_utc_iso_days(_iso_days, _zone), do: {:error, :time_zone_not_found}

    # Test/Gap skips 2026-03-08 00:00..01:00; Test/Fold repeats 2026-11-01 00:00..01:00.
    @impl true
    def time_zone_periods_from_wall_datetime(wall, "Test/Gap") do
      cond do
        NaiveDateTime.compare(wall, ~N[2026-03-08 00:00:00]) == :lt ->
          {:ok, @std}

        NaiveDateTime.compare(wall, ~N[2026-03-08 01:00:00]) == :lt ->
          {:gap, {@std, ~N[2026-03-08 00:00:00]}, {@dst, ~N[2026-03-08 01:00:00]}}

        true ->
          {:ok, @dst}
      end
    end

    def time_zone_periods_from_wall_datetime(wall, "Test/Fold") do
      cond do
        NaiveDateTime.compare(wall, ~N[2026-11-01 00:00:00]) == :lt -> {:ok, @dst}
        NaiveDateTime.compare(wall, ~N[2026-11-01 01:00:00]) == :lt -> {:ambiguous, @dst, @std}
        true -> {:ok, @std}
      end
    end

    def time_zone_periods_from_wall_datetime(_wall, _zone), do: {:error, :time_zone_not_found}
  end

  describe "bounds/3 in a named zone" do
    test "uses the zone's midnight" do
      state = %PeriodFilter{period: "custom", from: ~D[2026-02-01], to: ~D[2026-02-02]}

      assert {:ok, ~U[2026-02-01 05:00:00Z], ~U[2026-02-03 05:00:00Z]} =
               PeriodFilter.bounds(state, "Test/Gap", FakeDb)
    end

    test "a midnight skipped by the clocks resolves to the instant after the gap" do
      state = %PeriodFilter{period: "custom", from: ~D[2026-03-07], to: ~D[2026-03-07]}

      assert {:ok, ~U[2026-03-07 05:00:00Z], ~U[2026-03-08 05:00:00Z]} =
               PeriodFilter.bounds(state, "Test/Gap", FakeDb)

      state = %PeriodFilter{period: "custom", from: ~D[2026-03-08], to: ~D[2026-03-08]}

      assert {:ok, ~U[2026-03-08 05:00:00Z], ~U[2026-03-09 04:00:00Z]} =
               PeriodFilter.bounds(state, "Test/Gap", FakeDb)
    end

    test "a repeated midnight resolves to the first occurrence" do
      state = %PeriodFilter{period: "custom", from: ~D[2026-10-31], to: ~D[2026-10-31]}

      assert {:ok, ~U[2026-10-31 04:00:00Z], ~U[2026-11-01 04:00:00Z]} =
               PeriodFilter.bounds(state, "Test/Fold", FakeDb)

      state = %PeriodFilter{period: "custom", from: ~D[2026-11-01], to: ~D[2026-11-01]}

      assert {:ok, ~U[2026-11-01 04:00:00Z], ~U[2026-11-02 05:00:00Z]} =
               PeriodFilter.bounds(state, "Test/Fold", FakeDb)
    end

    test "an unknown zone is refused" do
      state = PeriodFilter.parse(%{}, ~D[2026-10-11])

      assert {:error, "The date range cannot be resolved in this time zone."} =
               PeriodFilter.bounds(state, "Mars/Olympus", FakeDb)
    end
  end

  describe "clock/2" do
    @shell %{mode: :company, timezone: "Test/Gap", tz_db: FakeDb}

    test "follows the mode's zone" do
      assert %{timezone: "Test/Gap"} = PeriodFilter.clock(@shell, "Test/Fold")
      assert %{timezone: "Test/Fold"} = PeriodFilter.clock(%{@shell | mode: :local}, "Test/Fold")
      assert %{timezone: "Etc/UTC"} = PeriodFilter.clock(%{@shell | mode: :utc}, "Test/Fold")
    end

    test "falls back to UTC for an invalid zone" do
      assert %{timezone: "Etc/UTC", today: %Date{}} =
               PeriodFilter.clock(%{@shell | timezone: "Nowhere/Land"}, nil)

      assert %{timezone: "Etc/UTC"} = PeriodFilter.clock(%{@shell | mode: :local}, nil)
    end
  end
end
