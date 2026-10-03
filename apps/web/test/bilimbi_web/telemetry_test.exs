defmodule BilimbiWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Repo

  test "database metrics receive real Repo query timings in milliseconds" do
    timings = [:total_time, :decode_time, :query_time, :queue_time, :idle_time]

    metrics =
      Enum.filter(BilimbiWeb.Telemetry.metrics(), fn metric ->
        Enum.take(metric.name, 1) == [:bilimbi] and List.last(metric.name) in timings
      end)

    assert length(metrics) == length(timings)
    handler_id = {__MODULE__, make_ref()}
    query = "SELECT 42 AS telemetry_probe"

    :ok =
      :telemetry.attach_many(
        handler_id,
        Enum.uniq(Enum.map(metrics, & &1.event_name)),
        &__MODULE__.handle_query/4,
        {self(), query}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    # Sandbox ownership omits idle_time; use a real pool for this read-only probe.
    repo = start_supervised!({Repo, name: nil, pool: DBConnection.ConnectionPool, pool_size: 1})
    previous_repo = Repo.put_dynamic_repo(repo)

    try do
      assert %{rows: [[42]]} = Repo.query!(query)
    after
      Repo.put_dynamic_repo(previous_repo)
    end

    assert_receive {:query_timings, event, measurements, %{repo: Repo}}

    for timing <- timings do
      metric = Enum.find(metrics, &(List.last(&1.name) == timing))
      assert metric.event_name == event
      assert metric.unit == :millisecond
      native = Map.fetch!(measurements, timing)
      assert is_number(native) and native >= 0

      assert_in_delta metric.measurement.(measurements),
                      native / System.convert_time_unit(1, :millisecond, :native),
                      0.000001
    end
  end

  def handle_query(event, measurements, %{query: query} = metadata, {pid, query}) do
    send(pid, {:query_timings, event, measurements, metadata})
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok
end
