defmodule Bilimbi.Base.UI.PeriodFilter do
  @moduledoc """
  Canonical calendar-day filter state for list and history pages.

  Ported from Belimbing's FiltersByPeriod: presets include both endpoints,
  this month includes the whole month, and the default is Last 30 days.
  `parse/2` reads `period`, `from`, and `to`; `params/1` writes them back.
  Pass the calendar's current date to `parse/2` when using another clock.
  `bounds/3` returns UTC instants with an exclusive upper bound, avoiding
  timestamp precision loss and respecting daylight-saving day lengths.
  The compact `<.period_filter>` owns selection, drafts and cancellation;
  callers keep applied state in their URL and supply its patch-path function.
  """
  defstruct period: "last_30_days", from: nil, to: nil

  @doc "Resolves the same calendar as timestamp display; browser zone is used only in Local mode."
  def clock(%{mode: mode, timezone: company_zone, tz_db: tz_db}, browser_zone) do
    tz_db = tz_db || Calendar.get_time_zone_database()

    zone =
      case mode do
        :company -> company_zone
        :local -> browser_zone || "Etc/UTC"
        :utc -> "Etc/UTC"
      end

    case now(zone, tz_db) do
      {:ok, instant} -> %{timezone: zone, tz_db: tz_db, today: DateTime.to_date(instant)}
      _ -> %{timezone: "Etc/UTC", tz_db: tz_db, today: Date.utc_today()}
    end
  end

  defp now(zone, tz_db) when is_binary(zone) and byte_size(zone) <= 64,
    do: DateTime.now(zone, tz_db)

  defp now(_, _), do: {:error, :invalid_time_zone}

  def options do
    [
      {"Today", "today"},
      {"This month", "this_month"},
      {"Last 7 days", "last_7_days"},
      {"Last 30 days", "last_30_days"},
      {"Last 90 days", "last_90_days"},
      {"Custom range", "custom"}
    ]
  end

  def parse(params, today \\ Date.utc_today()) do
    period = Map.get(params, "period", "last_30_days")
    period = if Enum.any?(options(), &(elem(&1, 1) == period)), do: period, else: "last_30_days"

    {from, to} =
      case period do
        "today" ->
          {today, today}

        "this_month" ->
          {Date.beginning_of_month(today), Date.end_of_month(today)}

        "last_7_days" ->
          {Date.add(today, -6), today}

        "last_90_days" ->
          {Date.add(today, -89), today}

        "custom" ->
          {parse_date(Map.get(params, "from"), Date.add(today, -29)),
           parse_date(Map.get(params, "to"), today)}

        _ ->
          {Date.add(today, -29), today}
      end

    %__MODULE__{period: period, from: from, to: to}
  end

  def custom(from, to) do
    with {:ok, first} <- Date.from_iso8601(from),
         {:ok, last} <- Date.from_iso8601(to) do
      if Date.compare(first, last) == :gt,
        do: {:error, "Start date must be on or before end date."},
        else: {:ok, %__MODULE__{period: "custom", from: first, to: last}}
    else
      _ -> {:error, "Choose a valid start and end date."}
    end
  end

  def params(%__MODULE__{} = state) do
    %{
      "period" => state.period,
      "from" => Date.to_iso8601(state.from),
      "to" => Date.to_iso8601(state.to)
    }
  end

  def bounds(state, timezone \\ "Etc/UTC", tz_db \\ Calendar.get_time_zone_database())

  def bounds(%__MODULE__{from: from, to: to}, timezone, tz_db) do
    if Date.compare(from, to) == :gt do
      {:error, "Start date must be on or before end date."}
    else
      with {:ok, first} <- day_start(from, timezone, tz_db),
           {:ok, after_last} <- day_start(Date.add(to, 1), timezone, tz_db) do
        {:ok, DateTime.shift_zone!(first, "Etc/UTC", tz_db),
         DateTime.shift_zone!(after_last, "Etc/UTC", tz_db)}
      else
        _ -> {:error, "The date range cannot be resolved in this time zone."}
      end
    end
  end

  defp day_start(date, timezone, tz_db) do
    case DateTime.new(date, ~T[00:00:00], timezone, tz_db) do
      {:ok, midnight} -> {:ok, midnight}
      {:gap, _just_before, just_after} -> {:ok, just_after}
      {:ambiguous, first, _second} -> {:ok, first}
      {:error, _} = error -> error
    end
  end

  defp parse_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> fallback
    end
  end

  defp parse_date(_, fallback), do: fallback
end
