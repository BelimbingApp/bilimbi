defmodule Bilimbi.Base.Queue.WorkerTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Queue.TestWorkers.Retry
  alias Bilimbi.Base.Queue.TestWorkers.Success

  test "worker adapter validates and maps the bounded result vocabulary" do
    success_adapter = Success.__queue_worker__().adapter
    retry_adapter = Retry.__queue_worker__().adapter

    assert :ok =
             success_adapter.perform(%Oban.Job{
               id: 1,
               args: %{"value" => 1},
               attempt: 1,
               max_attempts: 3,
               queue: "default"
             })

    assert {:cancel, :invalid_value} =
             success_adapter.perform(%Oban.Job{
               id: 2,
               args: %{"wrong" => 1},
               attempt: 1,
               max_attempts: 3,
               queue: "default"
             })

    assert {:error, :temporary_failure} =
             retry_adapter.perform(%Oban.Job{
               id: 3,
               args: %{"outcome" => "retry"},
               attempt: 1,
               max_attempts: 2,
               queue: "default"
             })

    assert {:cancel, :permanent_failure} =
             retry_adapter.perform(%Oban.Job{
               id: 4,
               args: %{"outcome" => "cancel"},
               attempt: 1,
               max_attempts: 2,
               queue: "default"
             })
  end

  test "worker identity and transport policy are compile-time facts" do
    assert %{id: "test/success", adapter: adapter} = Success.__queue_worker__()
    assert adapter.__queue_worker_id__() == "test/success"
    assert adapter.__opts__()[:queue] == :default
    assert adapter.__opts__()[:max_attempts] == 3
  end

  test "worker declarations reject queues the runtime does not consume" do
    assert_raise ArgumentError, ~r/requires the :default queue/, fn ->
      Code.compile_string("""
      defmodule Bilimbi.Base.Queue.TestWorkers.UnsupportedQueue do
        use Bilimbi.Base.Queue.Worker,
          id: "test/unsupported-queue",
          queue: :critical

        def validate_args(args), do: {:ok, args}
        def handle_job(_args, _execution), do: :ok
      end
      """)
    end
  end
end
