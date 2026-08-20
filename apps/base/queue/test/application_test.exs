defmodule Bilimbi.Base.Queue.ApplicationTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.Application, as: QueueApplication
  alias Bilimbi.Base.Queue.Migrations.CreateObanRuntime
  alias Bilimbi.Base.Queue.TestWorkers.Blocking
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  test "production configuration defines a validated graceful shutdown policy" do
    config = Queue.oban_config() |> Keyword.delete(:testing)

    assert config[:repo] == Bilimbi.Base.Repo
    assert config[:name] == Bilimbi.Base.Queue.Oban
    assert config[:prefix] == "public"
    assert config[:queues] == [default: 10]
    assert config[:plugins] == [{Oban.Plugins.Pruner, max_age: 604_800}]
    assert config[:shutdown_grace_period] == 15_000
    assert :ok = Oban.Config.validate(config)
    assert [{Oban, ^config}] = QueueApplication.children(config)
  end

  test "manual test mode supervises Oban without consumers or plugins" do
    config = Queue.oban_config()

    assert config[:testing] == :manual
    assert [{Oban, ^config}] = QueueApplication.children(config)
    assert is_pid(Oban.whereis(config[:name]))

    normalized = Oban.Config.new(config)
    assert normalized.queues == []
    assert normalized.plugins == []
    assert normalized.stage_interval == :infinity
  end

  test "shutdown drains an in-flight job within the configured grace period" do
    Process.register(self(), Bilimbi.Base.Queue.ShutdownTestListener)

    name = Module.concat(__MODULE__, "GracefulOban")

    schema =
      "queue_shutdown_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    quoted_schema = SchemaVerifier.quote_identifier!(schema)
    repo_name = start_isolated_repo!()
    previous_dynamic_repo = Repo.put_dynamic_repo(repo_name)

    SQL.query!(repo_name, "CREATE SCHEMA #{quoted_schema}", [])

    Ecto.Migrator.run(
      Repo,
      [{20_260_820_130_000, CreateObanRuntime}],
      :up,
      all: true,
      log: false,
      prefix: schema,
      dynamic_repo: repo_name
    )

    config =
      Queue.oban_config()
      |> Keyword.put(:name, name)
      |> Keyword.put(:prefix, schema)
      |> Keyword.put(:get_dynamic_repo, fn -> repo_name end)
      |> Keyword.delete(:testing)
      |> Keyword.put(:plugins, [])
      |> Keyword.put(:peer, false)
      |> Keyword.put(:queues, default: 1)
      |> Keyword.put(:shutdown_grace_period, 1_000)

    try do
      oban_pid = start_supervised!({Oban, config})
      adapter = Blocking.__queue_worker__().adapter
      assert {:ok, job} = Oban.insert(name, adapter.new(%{"value" => 1}))
      assert_receive {:queue_worker_started, worker_pid}, 2_000

      parent = self()

      {stopper_pid, stopper_ref} =
        spawn_monitor(fn ->
          send(parent, :queue_shutdown_started)
          Supervisor.stop(oban_pid)
          send(parent, :queue_shutdown_finished)
        end)

      assert_receive :queue_shutdown_started
      refute_receive :queue_shutdown_finished
      send(worker_pid, :release_queue_worker)
      assert_receive :queue_shutdown_finished, 2_000
      assert_receive {:DOWN, ^stopper_ref, :process, ^stopper_pid, :normal}
      prefixed_jobs = Ecto.Query.put_query_prefix(Oban.Job, schema)
      assert Repo.get!(prefixed_jobs, job.id).state == "completed"
    after
      _ = stop_supervised(name)
      Repo.put_dynamic_repo(repo_name)
      SQL.query!(repo_name, "DROP SCHEMA #{quoted_schema} CASCADE", [])
      Repo.put_dynamic_repo(previous_dynamic_repo)
      Process.unregister(Bilimbi.Base.Queue.ShutdownTestListener)
    end
  end

  defp start_isolated_repo! do
    name = Module.concat(__MODULE__, "Repo#{System.unique_integer([:positive, :monotonic])}")

    options =
      Repo.config()
      |> Keyword.put(:name, name)
      |> Keyword.put(:pool_size, 4)

    {Repo, options}
    |> Supervisor.child_spec(id: name)
    |> start_supervised!()

    previous_dynamic_repo = Repo.put_dynamic_repo(name)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Repo.put_dynamic_repo(previous_dynamic_repo)
    name
  end
end
