defmodule Bilimbi.Base.PerfTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Perf.Reporter
  alias Bilimbi.Base.Perf.RuntimeSampler
  alias Bilimbi.Base.Perf.Sample
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures

  setup do
    SettingsFixtures.create_settings_table!()
    Repo.delete_all(Sample)
    put_settings()
    :sys.get_state(Reporter)

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "records only a stable route identity and bounded measurements" do
    started = System.monotonic_time()

    Perf.handle_event(
      [:phoenix, :router_dispatch, :start],
      %{monotonic_time: started},
      %{route: "/users/:id", conn: %{query_string: "token=secret"}},
      nil
    )

    Perf.handle_event(
      [:bilimbi, :base, :repo, :query],
      %{total_time: System.convert_time_unit(7, :millisecond, :native)},
      %{query: "SELECT secret", params: ["credential"]},
      nil
    )

    Perf.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      %{conn: %{status: 200, resp_body: String.duplicate("x", 2_000)}},
      nil
    )

    synchronize_reporter()

    assert %Sample{
             kind: "request",
             identity: "/users/:id",
             outcome: "ok",
             duration_ms: 250,
             db_count: 1,
             db_duration_ms: 7,
             response_size_class: "1k_10k"
           } = Repo.one!(Sample)

    stored = Repo.one!(from(sample in Sample, select: sample.identity))
    refute stored =~ "secret"
    refute stored =~ "token"
  end

  test "exception clears observation state and records no exception payload" do
    Perf.handle_event(
      [:phoenix, :router_dispatch, :start],
      %{monotonic_time: System.monotonic_time()},
      %{route: "/reports"},
      nil
    )

    Perf.handle_event(
      [:phoenix, :router_dispatch, :exception],
      %{duration: System.convert_time_unit(150, :millisecond, :native)},
      %{kind: :error, reason: RuntimeError.exception("credential"), stacktrace: [secret: 1]},
      nil
    )

    synchronize_reporter()
    assert %Sample{identity: "/reports", outcome: "error"} = Repo.one!(Sample)

    Perf.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: System.convert_time_unit(200, :millisecond, :native)},
      %{conn: %{status: 200, resp_body: "ignored"}},
      nil
    )

    synchronize_reporter()
    assert Repo.aggregate(Sample, :count) == 1
  end

  test "forged unbounded route and worker identities fail closed" do
    Perf.handle_event(
      [:phoenix, :router_dispatch, :start],
      %{},
      %{route: "/search?credential=secret"},
      nil
    )

    Perf.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: System.convert_time_unit(500, :millisecond, :native)},
      %{conn: %{status: 200}},
      nil
    )

    Perf.handle_event(
      [:oban, :job, :start],
      %{},
      %{job: %{meta: %{"bilimbi_worker_id" => "Unsafe.Worker credential"}}},
      nil
    )

    Perf.handle_event(
      [:oban, :job, :stop],
      %{duration: System.convert_time_unit(500, :millisecond, :native)},
      %{state: :success},
      nil
    )

    synchronize_reporter()
    refute Repo.exists?(Sample)

    Reporter.submit(%{valid_attributes("/safe") | identity: "credential=secret"})
    synchronize_reporter()
    refute Repo.exists?(Sample)
  end

  test "records Queue outcomes by stable worker ID without arguments or errors" do
    generation = make_ref()

    Perf.handle_event(
      [:oban, :job, :start],
      %{system_time: System.system_time()},
      %{
        job: %{
          meta: %{"bilimbi_worker_id" => "base/report-export"},
          args: %{"credential" => "secret"}
        }
      },
      generation
    )

    Perf.handle_event(
      [:oban, :job, :stop],
      %{duration: System.convert_time_unit(300, :millisecond, :native)},
      %{state: :cancelled, result: {:cancel, RuntimeError.exception("secret")}},
      generation
    )

    synchronize_reporter()

    assert %Sample{kind: "job", identity: "base/report-export", outcome: "cancelled"} =
             Repo.one!(Sample)
  end

  test "classifies a real exhausted Oban job as discarded" do
    :ok = Perf.attach_handlers()
    on_exit(&Perf.detach_handlers/0)

    assert {:ok, _job} =
             %{"worker" => "missing"}
             |> Oban.Job.new(
               worker: "Bilimbi.MissingPerfWorker",
               max_attempts: 1,
               meta: %{"bilimbi_worker_id" => "base/exhausted"}
             )
             |> then(&Oban.insert(Queue.Oban, &1))

    assert %{discard: 1} = Oban.drain_queue(Queue.Oban, queue: :default)
    synchronize_reporter()
    assert %Sample{identity: "base/exhausted", outcome: "discarded"} = Repo.one!(Sample)
  end

  test "handler generation change cancels stale observations after reporter restart" do
    previous = make_ref()
    current = make_ref()

    Perf.handle_event(
      [:phoenix, :router_dispatch, :start],
      %{monotonic_time: System.monotonic_time()},
      %{route: "/stale"},
      previous
    )

    Perf.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: System.convert_time_unit(200, :millisecond, :native)},
      %{conn: %{status: 200}},
      current
    )

    synchronize_reporter()
    refute Repo.exists?(Sample)

    submit_request("/fresh")
    synchronize_reporter()
    assert %Sample{identity: "/fresh"} = Repo.one!(Sample)
  end

  test "runtime pressure samples are eligible even below request duration threshold" do
    put_settings(%{"perf.minimum_duration_ms" => 60_000})
    assert :ok = RuntimeSampler.sample_now()
    synchronize_reporter()

    assert %Sample{
             kind: "runtime",
             identity: "beam",
             duration_ms: 0,
             memory_bytes: memory,
             run_queue: run_queue
           } = Repo.one!(Sample)

    assert memory > 0
    assert run_queue >= 0
  end

  test "telemetry storms reserve only the configured bounded queue" do
    previous_max = Application.get_env(:bilimbi_base_perf, :max_pending)
    Application.put_env(:bilimbi_base_perf, :max_pending, 1)
    :sys.suspend(Reporter)

    on_exit(fn ->
      if Process.whereis(Reporter), do: :sys.resume(Reporter)

      if is_nil(previous_max) do
        Application.delete_env(:bilimbi_base_perf, :max_pending)
      else
        Application.put_env(:bilimbi_base_perf, :max_pending, previous_max)
      end
    end)

    dropped_before = Reporter.stats().dropped
    Enum.each(1..50, fn index -> Reporter.submit(valid_attributes("/storm/#{index}")) end)

    assert %{pending: 1, dropped: dropped} = Reporter.stats()
    assert dropped - dropped_before == 49
    assert Perf.diagnostics().recorder == :degraded

    :sys.resume(Reporter)
    synchronize_reporter()
    assert Repo.aggregate(Sample, :count) == 1
  end

  test "store failure drops telemetry without terminating the reporter or caller" do
    accepted_before = :sys.get_state(Reporter).accepted

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE base_perf_samples RENAME TO unavailable_perf_samples",
      []
    )

    try do
      assert :ok = Reporter.submit(valid_attributes("/business-completed"))
      assert %{accepted: ^accepted_before} = :sys.get_state(Reporter)
      assert Process.whereis(Reporter)
    after
      Ecto.Adapters.SQL.query!(
        Repo,
        "ALTER TABLE unavailable_perf_samples RENAME TO base_perf_samples",
        []
      )
    end
  end

  test "rejected samples do not repeat pruning at an acceptance boundary" do
    original_accepted = :sys.get_state(Reporter).accepted
    :sys.replace_state(Reporter, &%{&1 | accepted: 99})

    on_exit(fn ->
      :sys.replace_state(Reporter, &%{&1 | accepted: original_accepted})
    end)

    target = self()
    handler = "perf-prune-boundary-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:bilimbi, :base, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if String.starts_with?(metadata.query, "DELETE FROM \"base_perf_samples\"") do
            send(target, :prune_query)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :ok = Reporter.submit(valid_attributes("/accepted-boundary"))
    assert %{accepted: 100} = :sys.get_state(Reporter)
    assert_receive :prune_query
    assert_receive :prune_query
    refute_receive :prune_query

    put_settings(%{"perf.minimum_duration_ms" => 60_000})
    assert :ok = Reporter.submit(valid_attributes("/rejected-after-boundary"))
    assert %{accepted: 100} = :sys.get_state(Reporter)
    refute_receive :prune_query
  end

  test "disabled and unavailable settings fail closed without raising" do
    put_settings(%{"perf.enabled" => false})

    submit_request("/disabled")
    synchronize_reporter()
    refute Repo.exists?(Sample)

    ContributionRegistry.clear_for_test!()
    assert Perf.recording_enabled?() == false
    assert :ok = Reporter.submit(valid_attributes("/unavailable"))
    synchronize_reporter()
    refute Repo.exists?(Sample)
  end

  test "pruning enforces both age and row-count bounds" do
    put_settings(%{"perf.history.keep_days" => 10, "perf.history.max_rows" => 2})

    insert_sample!("/expired", DateTime.add(DateTime.utc_now(), -11, :day))
    insert_sample!("/oldest", DateTime.add(DateTime.utc_now(), -3, :second))
    insert_sample!("/middle", DateTime.add(DateTime.utc_now(), -2, :second))
    insert_sample!("/newest", DateTime.add(DateTime.utc_now(), -1, :second))

    assert {:ok, 2} = Perf.prune()

    assert ["/newest", "/middle"] =
             Repo.all(
               from(sample in Sample,
                 order_by: [desc: sample.observed_at],
                 select: sample.identity
               )
             )
  end

  test "concurrent node-equivalent writers and pruners converge on the global row cap" do
    put_settings(%{"perf.history.keep_days" => 10, "perf.history.max_rows" => 10})
    observed_at = DateTime.utc_now()

    1..120
    |> Task.async_stream(
      fn index ->
        insert_sample!("/concurrent/#{index}", DateTime.add(observed_at, index, :microsecond))
      end,
      max_concurrency: 8,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.each(fn result -> assert {:ok, %Sample{}} = result end)

    1..4
    |> Task.async_stream(fn _index -> Perf.prune() end,
      max_concurrency: 4,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.each(fn result -> assert {:ok, {:ok, _deleted}} = result end)

    assert Repo.aggregate(Sample, :count) == 10
  end

  test "list is stably paginated and validates filters before querying" do
    observed_at = DateTime.utc_now()
    first = insert_sample!("/same", observed_at)
    second = insert_sample!("/same", observed_at)

    assert {:ok, %{entries: [entry, older], total: 2, page: 1, page_size: 25}} =
             Perf.list_samples(identity: "/same", page: 1, page_size: 25)

    assert entry.id == second.id
    assert older.id == first.id
    assert {:error, :invalid_options} = Perf.list_samples(page_size: 10)
    assert {:error, :invalid_options} = Perf.list_samples(identity: String.duplicate("x", 256))
  end

  test "regression diagnostics require explicit disjoint windows and deterministic sample floors" do
    baseline_from = ~U[2026-08-20 01:00:00Z]
    baseline_to = ~U[2026-08-20 02:00:00Z]
    current_from = ~U[2026-08-20 03:00:00Z]
    current_to = ~U[2026-08-20 04:00:00Z]

    Enum.each(1..5, fn second ->
      insert_sample!("/reports", DateTime.add(baseline_from, second, :second), 100)
      insert_sample!("/reports", DateTime.add(current_from, second, :second), 2_000)
    end)

    assert {:ok,
            [
              %{
                identity: "/reports",
                baseline_samples: 5,
                current_samples: 5,
                current_p95_ms: 2_000.0,
                delta_percent: 1_900.0,
                slow?: true
              }
            ]} =
             Perf.regressions(
               baseline_from: baseline_from,
               baseline_to: baseline_to,
               current_from: current_from,
               current_to: current_to,
               min_samples: 5
             )

    assert {:error, :invalid_options} =
             Perf.regressions(
               baseline_from: baseline_from,
               baseline_to: current_to,
               current_from: current_from,
               current_to: current_to,
               min_samples: 5
             )
  end

  test "regression diagnostics bound high-cardinality candidates in SQL" do
    baseline_from = ~U[2026-08-20 01:00:00Z]
    baseline_to = ~U[2026-08-20 02:00:00Z]
    current_from = ~U[2026-08-20 03:00:00Z]
    current_to = ~U[2026-08-20 04:00:00Z]
    handler = "perf-regression-query-#{System.unique_integer([:positive])}"

    Enum.each(1..30, fn index ->
      Enum.each(1..5, fn sample ->
        insert_sample!(
          "/candidate/#{index}",
          DateTime.add(baseline_from, index * 10 + sample, :second),
          100
        )

        insert_sample!(
          "/candidate/#{index}",
          DateTime.add(current_from, index * 10 + sample, :second),
          2_000
        )
      end)
    end)

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _event, _measurements, metadata, target ->
        send(target, {:regression_query, metadata.query})
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, rows} =
             Perf.regressions(
               baseline_from: baseline_from,
               baseline_to: baseline_to,
               current_from: current_from,
               current_to: current_to,
               min_samples: 5,
               limit: 3
             )

    assert length(rows) == 3
    assert_receive {:regression_query, query}
    assert query =~ "LIMIT"
  end

  defp synchronize_reporter, do: :sys.get_state(Reporter)

  defp submit_request(route) do
    Perf.handle_event(
      [:phoenix, :router_dispatch, :start],
      %{monotonic_time: System.monotonic_time()},
      %{route: route},
      nil
    )

    Perf.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      %{conn: %{status: 200, resp_body: "ok"}},
      nil
    )
  end

  defp insert_sample!(identity, observed_at, duration \\ 250) do
    %Sample{}
    |> Sample.changeset(%{valid_attributes(identity, observed_at) | duration_ms: duration})
    |> Repo.insert!()
  end

  defp valid_attributes(identity, observed_at \\ DateTime.utc_now()) do
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

  defp put_settings(overrides \\ %{}) do
    defaults = %{
      "perf.enabled" => true,
      "perf.minimum_duration_ms" => 0,
      "perf.sample_rate" => 1.0,
      "perf.slow_threshold_ms" => 1_000,
      "perf.history.keep_days" => 30,
      "perf.history.max_rows" => 200_000
    }

    definitions =
      defaults
      |> Map.merge(overrides)
      |> Map.new(fn {key, default} ->
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
      graph_fingerprint: "perf-test",
      consumers: %{
        settings: %{definitions: definitions, runtime_claims: []}
      }
    })
  end
end
