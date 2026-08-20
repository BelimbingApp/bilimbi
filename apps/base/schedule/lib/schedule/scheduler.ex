defmodule Bilimbi.Base.Schedule.Scheduler do
  @moduledoc false

  use GenServer
  require Logger

  alias Bilimbi.Base.Schedule
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.Recurrence

  @application :bilimbi_base_schedule
  @default_poll_interval 15_000

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  @impl true
  def init(_options) do
    send(self(), :poll)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    poll()
    Process.send_after(self(), :poll, poll_interval())
    {:noreply, state}
  end

  @doc false
  def poll(now \\ DateTime.utc_now()) do
    Schedule.reconcile_terminal_occurrences()
    Enum.each(Schedule.definitions(), &enqueue_latest_due(&1, now))
    :ok
  rescue
    error in ArgumentError ->
      Logger.warning(
        "schedule registry unavailable; recurrence poll skipped: #{Exception.message(error)}"
      )

      :ok
  catch
    :exit, _reason ->
      Logger.warning("schedule registry unavailable; recurrence poll skipped")
      :ok
  end

  defp enqueue_latest_due(%Definition{} = definition, now) do
    with {:ok, local_intended} <- Recurrence.previous_occurrence(definition, now) do
      intended_at = DateTime.shift_zone!(local_intended, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
      latest = Schedule.latest_scheduled_occurrence(definition)

      if is_nil(latest) or DateTime.before?(latest, intended_at) do
        case Schedule.enqueue_due(definition, intended_at) do
          {:ok, _job} ->
            :ok

          {:error, reason}
          when reason in [:already_claimed, :disabled, :overlap, :suppressed, :unreviewed] ->
            :ok

          {:error, reason} ->
            diagnostic(definition, reason)
        end
      end
    else
      _error -> diagnostic(definition, :time_resolution_failed)
    end
  end

  defp diagnostic(definition, reason) do
    Logger.warning("schedule occurrence was not enqueued",
      schedule_key: definition.key,
      schedule_owner: definition.owner,
      schedule_reason: reason
    )
  end

  defp poll_interval do
    case Application.get_env(@application, :poll_interval, @default_poll_interval) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_poll_interval
    end
  end
end
