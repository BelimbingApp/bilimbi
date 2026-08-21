defmodule Bilimbi.Base.ScheduleTest do
  use Bilimbi.Base.Database.DataCase, async: false

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.JobRef
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.FinalizeFailureTestWorker
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.RetryOnceTestWorker
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.Scheduler
  alias Bilimbi.Base.Schedule.Suppression
  alias Bilimbi.Base.Schedule.TestWorker
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope
  alias Crontab.CronExpression.Parser

  setup do
    SettingsFixtures.create_settings_table!()
    AuditFixtures.create_audit_tables!()
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
    on_exit(fn -> Application.delete_env(:bilimbi_base_schedule, :test_recipient) end)
    %{definition: definition}
  end

  test "operator task summaries expose immutable schedule facts without worker arguments", %{
    definition: definition
  } do
    definition = %{definition | owner: "base/perf", owner_route: "/system/performance"}
    put_definitions([definition])

    Repo.insert!(%Run{
      source: "scheduler",
      key: definition.key,
      name: definition.task_name,
      status: "failed",
      started_at: ~N[2026-08-20 12:00:00],
      finished_at: ~N[2026-08-20 12:00:02],
      runtime_ms: 2_000,
      output_excerpt: "secret-output-must-not-leak"
    })

    assert {:ok, [task]} = Schedule.list_tasks(search: "TEST", status: "unreviewed")
    assert task.key == definition.key
    assert task.owner == "base/perf"
    assert task.owner_route == "/system/performance"
    assert task.expression == "30 1 * * *"
    assert task.timezone == "America/New_York"
    assert task.overlap == :forbid
    assert task.misfire == :coalesce
    assert task.last_status == :failed
    assert task.last_runtime_ms == 2_000
    refute Map.has_key?(task, :args)
    refute Map.has_key?(task, :output_excerpt)

    assert {:ok, []} = Schedule.list_tasks(status: "succeeded")
    assert {:error, :invalid_options} = Schedule.list_tasks(page_size: 500)
    assert {:error, :invalid_options} = Schedule.list_tasks(search: String.duplicate("x", 256))
  end

  test "history filtering and pagination happen in the database with exact totals", %{
    definition: definition
  } do
    Enum.each(1..30, fn offset ->
      Repo.insert!(%Run{
        source: "scheduler",
        key: definition.key,
        name: "Test schedule #{offset}",
        status: if(rem(offset, 2) == 0, do: "succeeded", else: "failed"),
        started_at: NaiveDateTime.add(~N[2026-08-01 00:00:00], offset, :hour),
        output_excerpt: "private payload #{offset}"
      })
    end)

    assert {:ok, page} =
             Schedule.list_runs(
               search: "Test schedule",
               status: "succeeded",
               start_date: ~D[2026-08-01],
               end_date: ~D[2026-08-03],
               sort_by: :started_at,
               sort_dir: :asc,
               page: 1,
               page_size: 25
             )

    assert page.total_entries == 15
    assert page.total_pages == 1
    assert length(page.entries) == 15

    assert Enum.map(page.entries, & &1.started_at) ==
             Enum.sort(Enum.map(page.entries, & &1.started_at))

    assert Enum.all?(page.entries, &(&1.status == "succeeded"))
    refute Map.has_key?(hd(page.entries), :output_excerpt)

    assert {:ok, second_page} = Schedule.list_runs(page: 2, page_size: 25)
    assert second_page.total_entries == 30
    assert second_page.total_pages == 2
    assert length(second_page.entries) == 5

    assert {:error, :invalid_options} =
             Schedule.list_runs(start_date: ~D[2026-08-03], end_date: ~D[2026-08-01])

    assert {:error, :invalid_options} = Schedule.list_runs(search: String.duplicate("x", 256))
  end

  test "operator commands persist actor-attributed audit facts and reject stale definitions", %{
    definition: definition
  } do
    actor = actor()

    assert :ok = Schedule.review_definition(actor, definition.key, true)
    assert :ok = Schedule.suppress(actor, definition.key)
    assert :ok = Schedule.resume(actor, definition.key)
    assert {:ok, 45} = Schedule.set_history_retention(actor, 45)
    assert Settings.get("schedule.history.keep_days") == 45

    assert {:ok, actions} = Audit.list_actions(actor.scope)

    assert Enum.map(actions, & &1.event) == [
             "schedule.task.enabled",
             "schedule.task.paused",
             "schedule.task.resumed",
             "schedule.retention.changed"
           ]

    assert Enum.all?(actions, &(&1.actor_type == "user" and &1.actor_id == actor.id))
    assert Enum.all?(actions, &(&1.company_id == actor.company_id))
    assert Enum.all?(actions, &(&1.payload["source"] == "scheduler"))

    assert {:error, :not_found} = Schedule.suppress(actor, "removed.definition")
    assert {:ok, unchanged} = Audit.list_actions(actor.scope)
    assert length(unchanged) == 4
    assert {:error, :invalid_retention} = Schedule.set_history_retention(actor, 3651)
  end

  test "diagnostics distinguish recorder failure from Queue evidence" do
    diagnostics = Schedule.diagnostics()
    assert diagnostics.queue == :available
    assert diagnostics.recorder == :available

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE base_schedule_runs RENAME TO unavailable_runs",
      []
    )

    failed = Schedule.diagnostics()
    assert failed.queue == :available
    assert failed.recorder == :unavailable
    assert failed.due_work == :none_due

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE unavailable_runs RENAME TO base_schedule_runs",
      []
    )
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

  test "suppression after enqueue cancels the queued occurrence before business execution", %{
    definition: definition
  } do
    Application.put_env(:bilimbi_base_schedule, :test_recipient, self())
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)
    assert :ok = Schedule.suppress(definition.key)

    assert %{cancelled: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    refute_received {:schedule_business_effect, _value}

    assert Repo.exists?(
             from occurrence in Occurrence,
               where:
                 occurrence.key == ^definition.key and occurrence.state == "failed" and
                   not is_nil(occurrence.finished_at) and is_nil(occurrence.overlap_key)
           )
  end

  test "a changed definition cannot execute a job claimed under its old fingerprint", %{
    definition: definition
  } do
    Application.put_env(:bilimbi_base_schedule, :test_recipient, self())
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)

    changed = %{definition | args: %{"value" => 8}}
    put_definitions([changed])
    assert :ok = Schedule.review_definition(changed.key, true)

    assert %{cancelled: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    refute_received {:schedule_business_effect, _value}
  end

  test "disabling a definition after enqueue cancels it before business execution", %{
    definition: definition
  } do
    Application.put_env(:bilimbi_base_schedule, :test_recipient, self())
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)
    assert :ok = Schedule.review_definition(definition.key, false)

    assert %{cancelled: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    refute_received {:schedule_business_effect, _value}
  end

  test "terminal Queue cancellation and unavailable-worker discard release overlap on reconcile",
       %{
         definition: definition
       } do
    assert :ok = Schedule.review_definition(definition.key, true)
    assert {:ok, %JobRef{id: cancelled_id}} = Schedule.run_now(definition.key)
    assert :ok = Queue.cancel(cancelled_id)
    assert {:ok, %JobRef{}} = Schedule.run_now(definition.key)

    assert %{success: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
    assert {:ok, %JobRef{id: unavailable_id}} = Schedule.run_now(definition.key)

    Repo.update_all(
      from(job in Oban.Job, where: job.id == ^unavailable_id),
      set: [worker: "Bilimbi.MissingScheduleWorker", max_attempts: 1]
    )

    assert %{discard: 1} = Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
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

  test "occurrence-finalization failure does not repeat business work and later reconciles", %{
    definition: definition
  } do
    Application.put_env(:bilimbi_base_schedule, :test_recipient, self())
    failing = %{definition | worker: FinalizeFailureTestWorker, args: %{}}
    put_definitions([failing])
    assert :ok = Schedule.review_definition(failing.key, true)
    assert {:ok, %JobRef{}} = Schedule.run_now(failing.key)

    drain_result =
      try do
        Oban.drain_queue(Bilimbi.Base.Queue.Oban, queue: :default)
      after
        restore_occurrence_table()
      end

    assert %{success: 1} = drain_result
    assert_received :schedule_business_committed
    refute_received :schedule_business_committed

    assert {:ok, %JobRef{}} = Schedule.run_now(failing.key)

    assert Repo.exists?(
             from occurrence in Occurrence,
               where:
                 occurrence.key == ^failing.key and occurrence.state == "succeeded" and
                   not is_nil(occurrence.finished_at)
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

  test "run-now fails closed when the contribution snapshot is unavailable" do
    ContributionRegistry.clear_for_test!()
    assert {:error, :unavailable} = Schedule.run_now("test.schedule")
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

  defp actor do
    scope =
      Scope.for_tenant(%Identity{
        id: 41,
        name: "Operator tenant",
        status: "active",
        is_platform_operator: true
      })

    Actor.new!(:user, 91, scope, 73)
  end

  defp restore_occurrence_table do
    case Ecto.Adapters.SQL.query!(
           Repo,
           "SELECT to_regclass('unavailable_occurrences')::text",
           []
         ).rows do
      [["unavailable_occurrences"]] ->
        Ecto.Adapters.SQL.query!(
          Repo,
          "ALTER TABLE unavailable_occurrences RENAME TO base_schedule_occurrences",
          []
        )

      [[nil]] ->
        :ok
    end
  end
end
