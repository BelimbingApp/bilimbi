defmodule Bilimbi.Base.ScheduleConcurrencyTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 60_000

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.Migrations.CreateObanRuntime
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.Migrations.CreateCompatibilityBaseline, as: CreateScheduleBaseline
  alias Bilimbi.Base.Schedule.Migrations.CreateOccurrenceRuntime
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.SchemaContract
  alias Bilimbi.Base.Schedule.TestWorker
  alias Bilimbi.Base.Settings.Migrations.CreateCompatibilityBaseline, as: CreateSettingsBaseline
  alias Crontab.CronExpression.Parser
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @queue_application :bilimbi_base_queue

  setup do
    require_migrations!()
    unique = System.unique_integer([:positive])
    database = "bilimbi_schedule_concurrency_#{unique}"
    quoted_database = SchemaVerifier.quote_identifier!(database)

    Sandbox.unboxed_run(Repo, fn -> SQL.query!(Repo, "CREATE DATABASE #{quoted_database}", []) end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)", [])
      end)
    end)

    original_repo_options = Application.fetch_env!(:bilimbi_base_database, Repo)

    concurrent_repo_options =
      Repo.config()
      |> Keyword.put(:database, database)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 2)

    Application.put_env(:bilimbi_base_database, Repo, concurrent_repo_options)
    on_exit(fn -> Application.put_env(:bilimbi_base_database, Repo, original_repo_options) end)

    repos =
      for role <- [:observer, :node_a, :node_b], into: %{} do
        name = Module.concat(__MODULE__, "Repo#{role}#{unique}")

        repo_pid =
          start_supervised!(
            Supervisor.child_spec(
              {Repo,
               name: name, database: database, pool: DBConnection.ConnectionPool, pool_size: 2},
              id: name
            )
          )

        {role, repo_pid}
      end

    assert Ecto.Repo.Registry.lookup(repos.observer).opts[:pool] ==
             DBConnection.ConnectionPool

    Ecto.Migrator.up(Repo, 20_260_811_093_952, CreateSettingsBaseline,
      log: false,
      dynamic_repo: repos.observer
    )

    Ecto.Migrator.up(Repo, 20_260_820_130_000, CreateObanRuntime,
      log: false,
      dynamic_repo: repos.observer
    )

    Ecto.Migrator.up(Repo, 20_260_813_114_301, CreateScheduleBaseline,
      log: false,
      dynamic_repo: repos.observer
    )

    Ecto.Migrator.up(Repo, 20_260_821_100_001, CreateOccurrenceRuntime,
      log: false,
      dynamic_repo: repos.observer
    )

    assert [["base_schedule_definition_reviews", "oban_jobs"]] =
             SQL.query!(
               repos.observer,
               "SELECT to_regclass('base_schedule_definition_reviews')::text, to_regclass('oban_jobs')::text",
               []
             ).rows

    queue_name = Module.concat(__MODULE__, "Oban#{unique}")
    originals = queue_environment()
    Application.put_env(@queue_application, :name, queue_name)
    Application.put_env(@queue_application, :queues, false)
    Application.put_env(@queue_application, :plugins, false)
    Application.put_env(@queue_application, :get_dynamic_repo, fn -> repos.observer end)

    oban_config =
      Queue.oban_config()
      |> Keyword.put(:queues, false)
      |> Keyword.put(:plugins, false)
      |> Keyword.put(:get_dynamic_repo, fn -> repos.observer end)

    {:ok, oban_pid} = with_repo(repos.observer, fn -> Oban.start_link(oban_config) end)
    Process.unlink(oban_pid)

    on_exit(fn ->
      try do
        Supervisor.stop(oban_pid)
      catch
        :exit, _reason -> :ok
      end
    end)

    definition = definition()

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "schedule-concurrency-test",
      consumers: %{schedule: %{definition.key => definition}}
    })

    with_repo(repos.observer, fn ->
      assert Repo.get_dynamic_repo() == repos.observer
      assert :ok = Schedule.review_definition(definition.key, true)
    end)

    on_exit(fn ->
      ContributionRegistry.clear_for_test!()
      restore_queue_environment(originals)
    end)

    %{definition: definition, repos: repos}
  end

  test "two database connections enqueue one job for one intended occurrence", %{
    definition: definition,
    repos: repos
  } do
    intended_at = ~U[2026-08-21 01:15:00Z]

    tasks =
      for repo <- [repos.node_a, repos.node_b] do
        Task.async(fn ->
          with_repo(repo, fn -> Schedule.enqueue_due(definition, intended_at) end)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, :infinity))

    assert Enum.count(results, &match?({:ok, _job}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_claimed})) == 1

    with_repo(repos.observer, fn ->
      assert Repo.aggregate(Occurrence, :count) == 1
      assert Repo.aggregate(Oban.Job, :count) == 1
    end)
  end

  test "fresh schema verifies exactly and rollback refuses retained operational state", %{
    repos: repos
  } do
    assert :ok = SchemaVerifier.verify(repos.observer, SchemaContract.tables())
    assert :ok = SchemaContract.verify_invariants(repos.observer, [])

    SQL.query!(
      repos.observer,
      "INSERT INTO base_schedule_runs (source, key, name, status, started_at) " <>
        "VALUES ('scheduler', 'invalid.task', 'Invalid task', 'unknown', now())",
      []
    )

    assert {:error, [message]} = SchemaContract.verify_invariants(repos.observer, [])
    assert message =~ "unknown live status values: unknown"

    SQL.query!(repos.observer, "DELETE FROM base_schedule_runs WHERE key = 'invalid.task'", [])

    assert_raise Postgrex.Error,
                 ~r/cannot roll back Base Schedule while occurrence claims or definition reviews exist/,
                 fn ->
                   Ecto.Migrator.down(Repo, 20_260_821_100_001, CreateOccurrenceRuntime,
                     log: false,
                     dynamic_repo: repos.observer
                   )
                 end

    SQL.query!(
      repos.observer,
      "TRUNCATE base_schedule_occurrences, base_schedule_definition_reviews",
      []
    )

    Ecto.Migrator.down(Repo, 20_260_821_100_001, CreateOccurrenceRuntime,
      log: false,
      dynamic_repo: repos.observer
    )

    SQL.query!(
      repos.observer,
      "INSERT INTO base_schedule_runs (source, key, name, status, started_at) " <>
        "VALUES ('scheduler', 'legacy.task', 'Legacy task', 'succeeded', now())",
      []
    )

    assert_raise Postgrex.Error,
                 ~r/cannot roll back Base Schedule while run history or suppressions exist/,
                 fn ->
                   Ecto.Migrator.down(Repo, 20_260_813_114_301, CreateScheduleBaseline,
                     log: false,
                     dynamic_repo: repos.observer
                   )
                 end

    assert [["base_schedule_runs"]] =
             SQL.query!(repos.observer, "SELECT to_regclass('base_schedule_runs')::text", []).rows
  end

  defp definition do
    {:ok, cron} = Parser.parse("15 1 * * *", false, [:prior, :subsequent])

    %Definition{
      key: "test.concurrent",
      name: "Concurrent schedule",
      expression: "15 1 * * *",
      cron: cron,
      timezone: "Etc/UTC",
      owner: "base/schedule",
      task_name: "Concurrent schedule",
      worker: TestWorker,
      args: %{"value" => 1},
      overlap: :forbid,
      misfire: :coalesce
    }
  end

  defp require_migrations! do
    for path <- [
          "../../settings/priv/repo/migrations/20260811093952_create_base_settings_compatibility_baseline.exs",
          "../../queue/priv/repo/migrations/20260820130000_create_base_queue_oban_runtime.exs",
          "../priv/repo/migrations/20260813114301_create_base_schedule_compatibility_baseline.exs",
          "../priv/repo/migrations/20260821100001_create_base_schedule_occurrence_runtime.exs"
        ] do
      Code.require_file(Path.expand(path, __DIR__))
    end
  end

  defp with_repo(repo_name, function) do
    previous = Repo.put_dynamic_repo(repo_name)

    try do
      function.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp queue_environment do
    for key <- [:name, :queues, :plugins, :get_dynamic_repo], into: %{} do
      {key, Application.get_env(@queue_application, key)}
    end
  end

  defp restore_queue_environment(environment) do
    Enum.each(environment, fn
      {key, nil} -> Application.delete_env(@queue_application, key)
      {key, value} -> Application.put_env(@queue_application, key, value)
    end)
  end
end
