defmodule Bilimbi.Base.Queue.DiagnosticsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.Diagnostics
  alias Bilimbi.Base.Queue.JobPage
  alias Bilimbi.Base.Queue.TestWorkers.Retry
  alias Bilimbi.Base.Queue.TestWorkers.Success

  test "diagnostics and pages expose fixed operational facts without payloads" do
    canary = "secret-canary-#{System.unique_integer([:positive])}"
    assert {:ok, _reference} = Queue.enqueue(Success, %{"value" => 1, "secret" => canary})

    assert %Diagnostics{available?: true, backlog: 1} = diagnostics = Queue.diagnostics()
    assert Queue.health_status() =~ "Available (1 pending"
    refute inspect(diagnostics) =~ canary

    assert {:ok, %JobPage{entries: [summary], total: 1, page_size: 25}} = Queue.list_jobs()
    assert summary.worker_id == "test/success"
    assert summary.available?
    refute Map.has_key?(Map.from_struct(summary), :args)
    refute inspect(summary) =~ canary
  end

  test "list options are bounded and fail closed" do
    assert {:error, :invalid_options} = Queue.list_jobs(page_size: 300)
    assert {:error, :invalid_options} = Queue.list_jobs(state: "unknown")
    assert {:error, :invalid_options} = Queue.list_jobs(queue: "critical")
    assert {:error, :invalid_options} = Queue.list_jobs(extra: true)
  end

  test "execution records completed, cancelled, and unavailable-worker terminal states" do
    assert {:ok, completed_ref} = Queue.enqueue(Success, %{"value" => 1})
    assert {:ok, cancelled_ref} = Queue.enqueue(Retry, %{"outcome" => "cancel"})

    assert {:ok, missing_job} =
             %{
               "worker" => "missing"
             }
             |> Oban.Job.new(
               worker: "Bilimbi.MissingQueueWorker",
               max_attempts: 1,
               meta: %{"bilimbi_worker_id" => "test/missing"}
             )
             |> then(&Oban.insert(Bilimbi.Base.Queue.Oban, &1))

    assert %{success: 1, cancelled: 1, discard: 1} =
             Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)

    assert {:ok, %JobPage{entries: entries}} = Queue.list_jobs(page_size: 25)
    summaries = Map.new(entries, &{&1.id, &1})

    assert summaries[completed_ref.id].state == :completed
    assert summaries[cancelled_ref.id].state == :cancelled
    assert summaries[missing_job.id].state == :discarded
    refute summaries[missing_job.id].available?
    assert summaries[missing_job.id].worker_id == "test/missing"
  end
end
