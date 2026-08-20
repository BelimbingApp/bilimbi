defmodule Bilimbi.Base.Schedule.Execution do
  @moduledoc false

  require Logger

  import Ecto.Query

  alias Bilimbi.Base.Queue.Execution, as: QueueExecution
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Settings

  @terminal_statuses ["failed", "skipped", "succeeded"]

  def run(worker, %{"__bilimbi_schedule__" => metadata} = args, %QueueExecution{} = execution) do
    business_args = Map.delete(args, "__bilimbi_schedule__")
    started = System.monotonic_time(:millisecond)
    run = best_effort_start(metadata)
    best_effort_prune()

    try do
      result = worker.handle_scheduled_job(business_args, execution)
      best_effort_finish(metadata, run, result, execution, started)
      result
    rescue
      error ->
        best_effort_exception(metadata, run, started)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        best_effort_exception(metadata, run, started)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp best_effort_start(metadata) do
    now = DateTime.utc_now()

    with %Occurrence{} = occurrence <- verified_occurrence(metadata),
         {_count, _rows} <-
           Repo.update_all(
             from(item in Occurrence,
               where: item.id == ^occurrence.id and is_nil(item.finished_at)
             ),
             set: [state: "running", started_at: now]
           ) do
      Repo.insert!(%Run{
        source: metadata["source"],
        key: metadata["key"],
        name: metadata["name"],
        expression: metadata["expression"],
        status: "running",
        started_at: naive_now()
      })
    else
      _invalid ->
        diagnostic(:start_unavailable, metadata)
        nil
    end
  rescue
    _error ->
      diagnostic(:start_unavailable, metadata)
      nil
  catch
    :exit, _reason ->
      diagnostic(:start_unavailable, metadata)
      nil
  end

  defp best_effort_finish(metadata, run, result, execution, started) do
    {status, terminal?, excerpt} = result_status(result, execution)
    now = DateTime.utc_now()

    if run do
      Repo.update_all(
        from(item in Run, where: item.id == ^run.id),
        set: [
          status: status,
          finished_at: DateTime.to_naive(now) |> NaiveDateTime.truncate(:second),
          runtime_ms: max(System.monotonic_time(:millisecond) - started, 0),
          output_excerpt: excerpt,
          updated_at: DateTime.to_naive(now) |> NaiveDateTime.truncate(:second)
        ]
      )
    end

    if terminal? do
      finish_occurrence(metadata, status, now)
    end
  rescue
    _error -> diagnostic(:finish_unavailable, metadata)
  catch
    :exit, _reason -> diagnostic(:finish_unavailable, metadata)
  end

  defp best_effort_exception(metadata, run, started) do
    best_effort_finish(
      metadata,
      run,
      {:cancel, :worker_exception},
      %QueueExecution{job_id: 0, attempt: 1, max_attempts: 1, queue: "default"},
      started
    )
  end

  defp result_status(:ok, _execution), do: {"succeeded", true, nil}

  defp result_status({:cancel, code}, _execution) when is_atom(code),
    do: {"failed", true, Atom.to_string(code)}

  defp result_status({:retry, code}, %{attempt: attempt, max_attempts: maximum})
       when is_atom(code),
       do: {"failed", attempt >= maximum, Atom.to_string(code)}

  defp result_status(_invalid, _execution), do: {"failed", true, "invalid_worker_result"}

  defp finish_occurrence(metadata, status, now) do
    Repo.update_all(
      from(item in Occurrence,
        where:
          item.id == ^metadata["occurrence_id"] and item.source == ^metadata["source"] and
            item.key == ^metadata["key"] and is_nil(item.finished_at)
      ),
      set: [state: status, finished_at: now, overlap_key: nil]
    )
  end

  defp verified_occurrence(metadata) do
    Repo.one(
      from(item in Occurrence,
        where:
          item.id == ^metadata["occurrence_id"] and item.source == ^metadata["source"] and
            item.key == ^metadata["key"] and
            item.intended_at == ^parse_time!(metadata["intended_at"]) and
            item.trigger == ^metadata["trigger"] and is_nil(item.finished_at)
      )
    )
  end

  defp best_effort_prune do
    case Settings.get("schedule.history.keep_days") do
      days when is_integer(days) and days in 1..3650 ->
        cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days, :day)

        Repo.delete_all(
          from(run in Run,
            where:
              (run.status in ^@terminal_statuses and run.finished_at < ^cutoff) or
                (run.status == "running" and run.started_at < ^cutoff)
          )
        )

      0 ->
        :ok

      _invalid ->
        Logger.warning(
          "schedule history retention is unavailable or outside 0..3650; pruning skipped"
        )
    end
  rescue
    _error -> Logger.warning("schedule history pruning unavailable")
  catch
    :exit, _reason -> Logger.warning("schedule history pruning unavailable")
  end

  defp parse_time!(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    datetime
  end

  defp naive_now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  defp diagnostic(code, metadata) do
    Logger.warning("schedule recorder #{code}",
      schedule_source: metadata["source"],
      schedule_key: metadata["key"]
    )
  end
end
