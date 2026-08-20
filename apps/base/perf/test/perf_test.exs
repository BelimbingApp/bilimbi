defmodule Bilimbi.Base.PerfTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Perf.Reporter
  alias Bilimbi.Base.Perf.Sample
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
      [:bilimbi, :repo, :query],
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

  defp insert_sample!(identity, observed_at) do
    %Sample{}
    |> Sample.changeset(valid_attributes(identity, observed_at))
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
