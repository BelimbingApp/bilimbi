defmodule Bilimbi.Base.ScheduleTest do
  use Bilimbi.Base.Database.DataCase, async: false

  import Ecto.Query

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.JobRef
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.RetryOnceTestWorker
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.Scheduler
  alias Bilimbi.Base.Schedule.Suppression
  alias Bilimbi.Base.Schedule.TestWorker
  alias Crontab.CronExpression.Parser

  setup do
    definition = definition()

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "schedule-test",
      consumers: %{
        schedule: %{definition.key => definition},
        settings: %{
          definitions: %{
            "schedule.history.keep_days" =>
              Bilimbi.Base.Settings.Definition.new!(
                "schedule.history.keep_days",
                "base/schedule",
                %{
                  type: :integer,
                  scopes: [:global],
                  default: 90
                }
              )
          },
          runtime_claims: []
        }
      }
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
    %{definition: definition}
  end

  test "new definitions fail closed until their exact fingerprint is reviewed", %{
    definition: definition
  } do
    assert {:error, :unreviewed} = Schedule.run_now(definition.key)
    assert :ok = Schedule.review_definition(definition.key, false)
    assert {:error, :disabled} = Schedule.run_now(definition.key)
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{conflict?: false}} = Schedule.run_now(definition.key)
  end

  test "suppression prevents both scheduled and manual enqueue", %{definition: definition} do
    assert :ok = Schedule.review_definition(definition.key, true)
    assert :ok = Schedule.suppress(definition.key)
    assert Repo.exists?(from row in Suppression, where: row.key == ^definition.key)
    assert {:error, :suppressed} = Schedule.run_now(definition.key)
    assert :ok = Schedule.resume(definition.key)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)
  end

  test "overlap remains closed until the Queue worker finishes", %{definition: definition} do
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)
    assert {:error, :overlap} = Schedule.run_now(definition.key)

    assert Repo.exists?(
             from row in Run,
               where:
                 row.key == ^definition.key and row.status == "skipped" and
                   row.output_excerpt == "overlap"
           )

    assert %{success: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)
  end

  test "a directly forged Queue job cannot bypass its durable occurrence claim", %{
    definition: definition
  } do
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{id: claimed_job_id}} = Schedule.run_now(definition.key)

    claimed_args =
      Repo.one!(from job in Oban.Job, where: job.id == ^claimed_job_id, select: job.args)

    assert {:ok, %JobRef{id: forged_job_id}} = Queue.enqueue(TestWorker, claimed_args)
    refute forged_job_id == claimed_job_id

    assert %{success: 1, cancelled: 1} =
             Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)

    assert Repo.aggregate(
             from(row in Bilimbi.Base.Schedule.Run,
               where: row.key == ^definition.key and row.status == "succeeded"
             ),
             :count
           ) == 1
  end

  test "recorder failure cannot reverse completed business work", %{definition: definition} do
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE base_schedule_runs RENAME TO unavailable_schedule_runs",
      []
    )

    assert %{success: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)

    assert Repo.exists?(
             from row in Occurrence,
               where:
                 row.key == ^definition.key and row.state == "succeeded" and
                   not is_nil(row.finished_at)
           )
  end

  test "a worker crash keeps the overlap lease through Queue retry", %{definition: definition} do
    retrying = %{definition | key: "test.retry", worker: RetryOnceTestWorker, args: %{}}
    put_definitions([retrying])
    assert :ok = Schedule.review_definition(retrying.key, true)
    assert {:ok, %JobRef{id: job_id}} = Schedule.run_now(retrying.key)

    assert %{failure: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    assert {:error, :overlap} = Schedule.run_now(retrying.key)

    assert :ok = Queue.retry(job_id)
    assert %{success: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    assert {:ok, %JobRef{}} = Schedule.run_now(retrying.key)
  end

  test "one intended occurrence is atomically claimed", %{definition: definition} do
    assert :ok = Schedule.review_definition(definition.key, true)
    intended = ~U[2026-08-21 01:15:00Z]

    assert {:ok, %JobRef{}} = Schedule.enqueue_due(definition, intended)
    assert {:error, reason} = Schedule.enqueue_due(definition, intended)
    assert reason in [:already_claimed, :overlap]
    assert Repo.aggregate(from(row in Occurrence, where: row.key == ^definition.key), :count) == 1
  end

  test "successful execution prunes only terminal history older than retention", %{
    definition: definition
  } do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    old = NaiveDateTime.add(now, -91, :day)
    recent = NaiveDateTime.add(now, -89, :day)

    Repo.insert!(%Run{
      source: "scheduler",
      key: "test.old",
      name: "Old run",
      status: "succeeded",
      started_at: old,
      finished_at: old
    })

    Repo.insert!(%Run{
      source: "scheduler",
      key: "test.recent",
      name: "Recent run",
      status: "succeeded",
      started_at: recent,
      finished_at: recent
    })

    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)
    assert %{success: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)

    refute Repo.exists?(from run in Run, where: run.key == "test.old")
    assert Repo.exists?(from run in Run, where: run.key == "test.recent")
  end

  test "coalescing selects only the latest missed local occurrence across DST", %{
    definition: definition
  } do
    assert :ok = Schedule.review_definition(definition.key, true)
    now = ~U[2026-11-01 07:00:00Z]
    assert :ok = Scheduler.poll(now)

    assert [intended] =
             Repo.all(
               from(row in Occurrence,
                 where: row.key == ^definition.key and row.trigger == "scheduled",
                 select: row.intended_at
               )
             )

    assert DateTime.compare(intended, ~U[2026-11-01 06:30:00Z]) == :eq
  end

  defp definition do
    {:ok, cron} = Parser.parse("30 1 * * *", false, [:prior, :subsequent])

    %Definition{
      key: "test.schedule",
      name: "Test schedule",
      expression: "30 1 * * *",
      cron: cron,
      timezone: "America/New_York",
      owner: "base/schedule",
      task_name: "Test recurrence",
      worker: TestWorker,
      args: %{"value" => 7},
      overlap: :forbid,
      misfire: :coalesce
    }
  end

  defp put_definitions(definitions) do
    snapshot = ContributionRegistry.snapshot!()
    schedule = Map.new(definitions, &{&1.key, &1})

    ContributionRegistry.put_snapshot_for_test!(
      put_in(snapshot, [:consumers, :schedule], schedule)
    )
  end
end
