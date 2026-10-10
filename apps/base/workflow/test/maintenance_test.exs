defmodule Bilimbi.Base.Workflow.MaintenanceTest do
  use Bilimbi.Base.Database.DataCase, async: false
  import Ecto.Query
  alias Bilimbi.Base.{Authz, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue.Execution
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures

  alias Bilimbi.Base.Workflow.{
    Contributions,
    EventSchema,
    MaintenanceWorker,
    OutboxSchema,
    RunSchema,
    TestListener,
    WorkSchema
  }

  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    create_tables!()
    install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    start_supervised!(TestListener)
    system = TenancyFixtures.scope()
    scope = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(system, 10, :user, 7, "admin.test.record.view", true)

    assert {:ok, :seeded} = Workflow.seed_definitions()
    %{scope: scope, subject: subject!(), system: system}
  end

  test "the maintenance definition is contributed every minute on a Schedule worker" do
    assert %{"base/workflow-maintenance" => definition} =
             Bilimbi.Base.Schedule.ContributionValidator.validate_contributions!([
               %{
                 descriptor: %{id: "base/workflow", otp_app: :bilimbi_base_workflow},
                 payload: Contributions.contributions().schedule
               }
             ])

    assert definition.expression == "* * * * *"
    assert definition.worker == MaintenanceWorker
    assert definition.overlap == :forbid
  end

  test "the sweep repairs an expired lease on every tenant's running run without owner authority",
       c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.retry", c.subject, idempotency_key: "sweep")

    assert {:ok, %{claim: claim}} = Workflow.claim_work(c.scope, "worker-1", lease_seconds: 60)

    Repo.update_all(from(w in WorkSchema, where: w.id == ^claim.work_item_id),
      set: [lease_expires_at: NaiveDateTime.add(now(), -5)]
    )

    # A run nobody can prove the tenant of is not a candidate.
    unresolved =
      Repo.get!(RunSchema, run.id)
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.merge(%{scope_type: "unresolved", tenant_id: nil, idempotency_key: "unresolved"})

    %RunSchema{} |> Ecto.Changeset.change(unresolved) |> Repo.insert!()

    assert {:ok, %{reconciled: 1, skipped: 0}} = Workflow.reconcile_running_runs()

    # Requeued, then released again in the same pass: it has no retry delay.
    assert %WorkSchema{status: "available", lease_token: nil, lease_owner: nil} =
             Repo.get!(WorkSchema, claim.work_item_id)

    assert Repo.exists?(
             from(e in EventSchema,
               where: e.process_run_id == ^run.id and e.type == "work.lease_expired_requeued"
             )
           )

    # Nobody signed in and no principal was named: the guest default records it.
    assert [["guest", 0, 1]] =
             Ecto.Adapters.SQL.query!(
               Repo,
               "SELECT actor_type, actor_id, tenant_id FROM base_audit_actions WHERE event = 'workflow.work.lease_expired_requeued'",
               []
             ).rows

    # The stale claim can no longer finish the item; the sweep is idempotent.
    assert {:error, :lease_not_owned} =
             Workflow.complete_claimed_work(c.scope, claim, %{
               outcome: "completed",
               output: [],
               result_ref: nil
             })

    assert {:ok, %{reconciled: 1}} = Workflow.reconcile_running_runs()
    assert Repo.aggregate(RunSchema, :count) == 2
  end

  test "a run whose definition is no longer installed is skipped unchanged", c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.parallel", c.subject,
               idempotency_key: "retired"
             )

    Repo.update_all(from(r in RunSchema, where: r.id == ^run.id),
      set: [definition_fingerprint: String.duplicate("0", 64)]
    )

    before = Repo.get!(RunSchema, run.id)
    assert {:ok, %{reconciled: 0, skipped: 1}} = Workflow.reconcile_running_runs()
    assert Repo.get!(RunSchema, run.id) == before
  end

  test "the scheduled job sweeps runs and delivers due events", c do
    assert {:ok, _} = Workflow.transition(c.scope, c.subject, "review")
    assert [row] = Repo.all(OutboxSchema)

    execution = %Execution{job_id: 1, attempt: 1, max_attempts: 3, queue: "default"}
    assert :ok = MaintenanceWorker.handle_scheduled_job(%{}, execution)

    assert %NaiveDateTime{} = Repo.get!(OutboxSchema, row.id).delivered_at
    assert [%{event: %{to_status: "review"}}] = TestListener.deliveries()
    assert {:error, :invalid_args} = MaintenanceWorker.validate_scheduled_args(%{"x" => 1})
  end

  test "sweep limits are bounded" do
    assert_raise ArgumentError, fn -> Workflow.reconcile_running_runs(limit: 0) end
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
