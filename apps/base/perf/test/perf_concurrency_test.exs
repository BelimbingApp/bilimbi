defmodule Bilimbi.Base.PerfConcurrencyTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 60_000

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Perf.Migrations.CreateSamples
  alias Bilimbi.Base.Perf.Reporter
  alias Bilimbi.Base.Perf.Sample
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Migrations.CreateCompatibilityBaseline, as: CreateSettingsBaseline
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    require_migrations!()
    unique = System.unique_integer([:positive])
    database = "bilimbi_perf_concurrency_#{unique}"
    quoted_database = SchemaVerifier.quote_identifier!(database)

    Sandbox.unboxed_run(Repo, fn -> SQL.query!(Repo, "CREATE DATABASE #{quoted_database}", []) end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)", [])
      end)
    end)

    repos =
      for role <- [:observer, :node_a, :node_b], into: %{} do
        name = Module.concat(__MODULE__, "Repo#{role}#{unique}")

        pid =
          start_supervised!(
            Supervisor.child_spec(
              {Repo,
               name: name, database: database, pool: DBConnection.ConnectionPool, pool_size: 2},
              id: name
            )
          )

        {role, pid}
      end

    assert Ecto.Repo.Registry.lookup(repos.node_a).opts[:pool] == DBConnection.ConnectionPool

    Ecto.Migrator.up(Repo, 20_260_811_093_952, CreateSettingsBaseline,
      log: false,
      dynamic_repo: repos.observer
    )

    Ecto.Migrator.up(Repo, 20_260_821_213_000, CreateSamples,
      log: false,
      dynamic_repo: repos.observer
    )

    put_settings()
    original_instrumentation = Application.get_env(:bilimbi_base_perf, :instrumentation_enabled)
    original_dynamic_repo = Application.get_env(:bilimbi_base_perf, :get_dynamic_repo)

    on_exit(fn ->
      restore_env(:instrumentation_enabled, original_instrumentation)
      restore_env(:get_dynamic_repo, original_dynamic_repo)
      restart_reporter!()
      ContributionRegistry.clear_for_test!()
    end)

    %{repos: repos}
  end

  test "real handlers restart cleanly and reporter SQL cannot recursively enqueue", %{
    repos: repos
  } do
    Application.put_env(:bilimbi_base_perf, :instrumentation_enabled, true)
    Application.put_env(:bilimbi_base_perf, :get_dynamic_repo, fn -> repos.observer end)
    restart_reporter!()

    repo_handler = "perf-repo-recursion-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        repo_handler,
        [:bilimbi, :base, :repo, :query],
        &Perf.handle_event/4,
        make_ref()
      )

    on_exit(fn -> :telemetry.detach(repo_handler) end)

    emit_job("base/perf-concurrency")
    :sys.get_state(Reporter)

    with_repo(repos.observer, fn ->
      assert Repo.aggregate(Sample, :count) == 1
    end)

    :telemetry.execute(
      [:oban, :job, :start],
      %{monotonic_time: System.monotonic_time()},
      %{job: %{meta: %{"bilimbi_worker_id" => "base/stale"}}}
    )

    restart_reporter!()

    :telemetry.execute(
      [:oban, :job, :stop],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      %{job: %{meta: %{"bilimbi_worker_id" => "base/stale"}}, state: :success}
    )

    :sys.get_state(Reporter)

    with_repo(repos.observer, fn ->
      assert Repo.aggregate(Sample, :count) == 1
    end)

    assert %{pending: 0} = Reporter.stats()
  end

  test "independent pooled connections converge after concurrent writes and pruning", %{
    repos: repos
  } do
    parent = self()
    observed_at = DateTime.utc_now()

    workers =
      [
        writer(repos.node_a, parent, observed_at, 1..600),
        writer(repos.node_b, parent, observed_at, 601..1200),
        pruner(repos.node_a, parent),
        pruner(repos.node_b, parent)
      ]

    Enum.each(workers, fn task ->
      assert_receive {:ready, pid} when pid == task.pid
    end)

    Enum.each(workers, &send(&1.pid, :go))
    Enum.each(workers, &Task.await(&1, :infinity))

    for repo <- [repos.node_a, repos.node_b] do
      with_repo(repo, fn -> assert {:ok, _deleted} = Perf.prune() end)
    end

    with_repo(repos.observer, fn ->
      assert Repo.aggregate(Sample, :count) == 1_000
    end)
  end

  defp writer(repo, parent, observed_at, range) do
    Task.async(fn ->
      with_repo(repo, fn ->
        send(parent, {:ready, self()})
        receive do: (:go -> :ok)

        range
        |> Enum.chunk_every(50)
        |> Enum.each(fn indexes ->
          rows =
            Enum.map(indexes, fn index ->
              valid_attributes(
                "/concurrent/#{index}",
                DateTime.add(observed_at, index, :microsecond)
              )
            end)

          {count, nil} = Repo.insert_all(Sample, rows)
          assert count == length(rows)
        end)
      end)
    end)
  end

  defp pruner(repo, parent) do
    Task.async(fn ->
      with_repo(repo, fn ->
        send(parent, {:ready, self()})
        receive do: (:go -> :ok)
        Enum.each(1..5, fn _iteration -> assert {:ok, _deleted} = Perf.prune() end)
      end)
    end)
  end

  defp emit_job(worker_id) do
    metadata = %{job: %{meta: %{"bilimbi_worker_id" => worker_id}}}

    :telemetry.execute(
      [:oban, :job, :start],
      %{monotonic_time: System.monotonic_time()},
      metadata
    )

    :telemetry.execute(
      [:oban, :job, :stop],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      Map.put(metadata, :state, :success)
    )
  end

  defp valid_attributes(identity, observed_at) do
    %{
      kind: "request",
      identity: identity,
      outcome: "ok",
      duration_ms: 250,
      db_duration_ms: 0,
      db_count: 0,
      memory_bytes: 1,
      run_queue: 0,
      observed_at: observed_at
    }
  end

  defp put_settings do
    defaults = %{
      "perf.enabled" => true,
      "perf.minimum_duration_ms" => 0,
      "perf.sample_rate" => 1.0,
      "perf.slow_threshold_ms" => 1_000,
      "perf.history.keep_days" => 30,
      "perf.history.max_rows" => 1_000
    }

    definitions =
      Map.new(defaults, fn {key, default} ->
        type =
          if is_float(default),
            do: :float,
            else: if(is_boolean(default), do: :boolean, else: :integer)

        {key,
         Definition.new!(key, "base/perf", %{
           type: type,
           scopes: [:global],
           default: default
         })}
      end)

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "perf-concurrency-test",
      consumers: %{settings: %{definitions: definitions, runtime_claims: []}}
    })
  end

  defp restart_reporter! do
    :ok = Supervisor.terminate_child(Bilimbi.Base.Perf.Supervisor, Reporter)
    {:ok, _pid} = Supervisor.restart_child(Bilimbi.Base.Perf.Supervisor, Reporter)
  end

  defp require_migrations! do
    for path <- [
          "../../settings/priv/repo/migrations/20260811093952_create_base_settings_compatibility_baseline.exs",
          "../priv/repo/migrations/20260821213000_create_base_perf_samples.exs"
        ] do
      Code.require_file(Path.expand(path, __DIR__))
    end
  end

  defp with_repo(repo, function) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      function.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:bilimbi_base_perf, key)
  defp restore_env(key, value), do: Application.put_env(:bilimbi_base_perf, key, value)
end
