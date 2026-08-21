defmodule Bilimbi.Base.Schedule.Recurrence do
  @moduledoc false

  alias Bilimbi.Base.Schedule.Definition
  alias Crontab.Scheduler

  @database TimeZoneInfo.TimeZoneDatabase

  @spec previous_occurrence(Definition.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def previous_occurrence(%Definition{} = definition, %DateTime{} = now) do
    case DateTime.shift_zone(now, definition.timezone, @database) do
      {:ok, local_now} -> find_previous(definition, DateTime.to_naive(local_now), now, 0)
      _error -> {:error, :invalid_timezone}
    end
  end

  @spec next_occurrence(Definition.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def next_occurrence(%Definition{} = definition, %DateTime{} = now) do
    case DateTime.shift_zone(now, definition.timezone, @database) do
      {:ok, local_now} -> find_next(definition, DateTime.to_naive(local_now), now, 0)
      _error -> {:error, :invalid_timezone}
    end
  end

  defp find_previous(_definition, _local_now, _now, attempts) when attempts >= 8,
    do: {:error, :unresolvable_time}

  defp find_previous(definition, local_now, now, attempts) do
    case Scheduler.get_previous_run_date(definition.cron, local_now) do
      {:ok, candidate} ->
        case DateTime.from_naive(candidate, definition.timezone, @database) do
          {:ok, intended} ->
            {:ok, intended}

          {:ambiguous, earlier, later} ->
            eligible = Enum.filter([earlier, later], &(DateTime.compare(&1, now) != :gt))

            case eligible do
              [] ->
                find_previous(
                  definition,
                  NaiveDateTime.add(candidate, -60, :second),
                  now,
                  attempts + 1
                )

              values ->
                {:ok, Enum.max_by(values, &DateTime.to_unix(&1, :microsecond))}
            end

          {:gap, _before, _after} ->
            find_previous(
              definition,
              NaiveDateTime.add(candidate, -60, :second),
              now,
              attempts + 1
            )

          {:error, _reason} ->
            {:error, :invalid_timezone}
        end

      _error ->
        {:error, :invalid_expression}
    end
  end

  defp find_next(_definition, _local_now, _now, attempts) when attempts >= 8,
    do: {:error, :unresolvable_time}

  defp find_next(definition, local_now, now, attempts) do
    case Scheduler.get_next_run_date(definition.cron, local_now) do
      {:ok, candidate} ->
        case DateTime.from_naive(candidate, definition.timezone, @database) do
          {:ok, intended} ->
            {:ok, intended}

          {:ambiguous, earlier, later} ->
            eligible = Enum.filter([earlier, later], &(DateTime.compare(&1, now) == :gt))

            case eligible do
              [] ->
                find_next(
                  definition,
                  NaiveDateTime.add(candidate, 60, :second),
                  now,
                  attempts + 1
                )

              values ->
                {:ok, Enum.min_by(values, &DateTime.to_unix(&1, :microsecond))}
            end

          {:gap, _before, after_gap} ->
            find_next(
              definition,
              DateTime.to_naive(after_gap),
              now,
              attempts + 1
            )

          {:error, _reason} ->
            {:error, :invalid_timezone}
        end

      _error ->
        {:error, :invalid_expression}
    end
  end
end
