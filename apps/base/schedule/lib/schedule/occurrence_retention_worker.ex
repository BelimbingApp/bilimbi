defmodule Bilimbi.Base.Schedule.OccurrenceRetentionWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "base/schedule-occurrence-retention",
    queue: :default,
    max_attempts: 5,
    unique_period: 3_600

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_args), do: {:error, :invalid_args}

  @impl true
  def handle_scheduled_job(%{}, _execution) do
    _deleted = Bilimbi.Base.Schedule.prune_occurrences()
    :ok
  rescue
    _error -> {:retry, :schedule_store_unavailable}
  catch
    :exit, _reason -> {:retry, :schedule_store_unavailable}
  end
end
