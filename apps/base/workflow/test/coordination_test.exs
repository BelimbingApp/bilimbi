defmodule Bilimbi.Base.Workflow.CoordinationTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.{Authz, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.{Authentication, ForgedActorError}

  alias Bilimbi.Base.Workflow.{
    DependencySchema,
    EventSchema,
    RunSchema,
    TestProcessContributions,
    WorkSchema
  }

  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    create_tables!()
    install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    system = Bilimbi.Base.Authz.TestFixtures.scope()
    scope = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(system, 10, :user, 7, "admin.test.record.view", true)

    %{scope: scope, subject: subject!(), system: system}
  end

  test "a retained in-flight graph continues with its original IDs, alias and carried input", c do
    subject = subject!(%{id: 41})

    saved =
      Bilimbi.Base.Workflow.LegacyCoordinationFixture.insert_in_flight!(
        Repo,
        Bilimbi.Base.Database.DataCase.temporary_schema!()
      )

    assert {:ok, %{run: retained, work_items: [completed | _]}} =
             Workflow.get_run(c.scope, saved.run_id)

    assert retained.definition_fingerprint == saved.fingerprint
    assert retained.subject_type == "Legacy\\Example\\Record"
    assert completed.result_ref == "owner-result:74" and completed.output == %{"saved_fact" => 74}
    old_events = events!(c.scope, saved.run_id)

    assert {:ok, replay} =
             Workflow.start_run(c.scope, "example.parallel", subject,
               idempotency_key: "retained-attempt",
               correlation_key: "owner-round:2",
               input: saved.input
             )

    assert replay.id == saved.run_id and replay.input == saved.input
    assert events!(c.scope, saved.run_id) == old_events

    for key <- ~w(second third) do
      assert {:ok, _} =
               Workflow.complete_work(
                 c.scope,
                 saved.run_id,
                 saved.items[key],
                 request("example." <> key)
               )
    end

    assert {:ok, %{run: %{status: "completed", input: input}, work_items: [first | rest]}} =
             Workflow.get_run(c.scope, saved.run_id)

    assert input == saved.input and first == completed
    assert Enum.map(rest, & &1.id) == [saved.items["second"], saved.items["third"]]
    assert Repo.aggregate(RunSchema, :count) == 1 and Repo.aggregate(WorkSchema, :count) == 3
    assert Enum.take(events!(c.scope, saved.run_id), 2) == old_events
  end

  test "process-only subjects need no seeded status flow and long start keys replay", c do
    entry = entry()

    registry =
      Bilimbi.Base.Workflow.ContributionValidator.validate_contributions!([
        %{
          entry
          | payload:
              entry.payload
              |> Map.put(:flows, [])
              |> Map.put(:processes, TestProcessContributions.processes())
        }
      ])

    snapshot = ContributionRegistry.snapshot!()
    ContributionRegistry.put_snapshot_for_test!(put_in(snapshot.consumers.workflow, registry))
    key = String.duplicate("k", 230)

    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.parallel", c.subject, idempotency_key: key)

    raw = "start:tenant:1:example.parallel:" <> key

    expected =
      binary_part(raw, 0, 170) <>
        ":" <> (:crypto.hash(:sha256, raw) |> Base.encode16(case: :lower))

    assert run.idempotency_key == expected

    assert {:ok, %{id: id}} =
             Workflow.start_run(c.scope, "example.parallel", c.subject, idempotency_key: key)

    assert id == run.id
    assert {:error, :flow_unavailable} = Workflow.record_initial(c.scope, c.subject)
    assert {:ok, %{entries: entries}} = Workflow.pending_work(c.scope)
    assert length(entries) == 3
  end

  test "parallel work and repeated start preserve IDs, versions and events", c do
    run = start!(c)

    assert {:ok, %{entries: items, next_cursor: nil}} =
             Workflow.pending_work(c.scope, subject: c.subject)

    assert Enum.map(items, & &1.step_key) == ~w(first second third)
    assert Enum.all?(items, &(&1.version == 1))
    events = events!(c.scope, run.id)
    assert Enum.map(events, & &1.sequence) == Enum.to_list(1..10)

    assert {:ok, repeated} =
             Workflow.start_run(c.scope, "example.parallel", c.subject,
               idempotency_key: "attempt:1"
             )

    assert repeated.id == run.id and events!(c.scope, run.id) == events

    assert {:error, :idempotency_conflict} =
             Workflow.start_run(c.scope, "example.parallel", c.subject,
               idempotency_key: "attempt:1",
               input: %{"different" => true}
             )

    assert Repo.aggregate(RunSchema, :count) == 1 and Repo.aggregate(WorkSchema, :count) == 3

    assert {:ok, _} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert {:ok, %{work_items: [first | _]}} = Workflow.get_run(c.scope, run.id)
    assert first.status == "completed" and first.version == 2

    assert {:error, :work_not_available} =
             Workflow.complete_work(c.scope, run.id, first.id, request("example.first"))
  end

  test "completion and owner effects roll back in the enclosing business transaction", c do
    run = start!(c)

    assert {:error, :business_refused} =
             Repo.transact(fn ->
               assert {:ok, _} =
                        Workflow.complete_work(
                          c.scope,
                          run.id,
                          %{step_key: "first"},
                          request("example.first")
                        )

               {:error, :business_refused}
             end)

    assert {:ok, %{entries: items}} = Workflow.pending_work(c.scope)
    assert length(items) == 3 and length(events!(c.scope, run.id)) == 10
    other = start!(c, input: %{"effect_then_refuse" => true}, idempotency_key: "refusal")

    assert {:error, :process_owner_refused} =
             Workflow.complete_work(
               c.scope,
               other.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert state(c.subject.id).marker == "original" and length(events!(c.scope, other.id)) == 10
  end

  test "versions, executors, owner attempt, tenant and forged actor fail closed", c do
    run = start!(c)

    assert {:error, :stale_work} =
             Workflow.complete_work(c.scope, run.id, %{step_key: "first"}, %{
               request("example.first")
               | expected_version: 2
             })

    assert {:error, :executor_mismatch} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("example.second")
             )

    other_scope = Authentication.sign_in(Bilimbi.Base.Authz.TestFixtures.scope(2), 7, 10)
    assert {:error, :run_not_found} = Workflow.get_run(other_scope, run.id)

    assert {:error, :run_not_found} =
             Workflow.complete_work(
               other_scope,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert {:error, :no_authenticated_actor} = Workflow.reconcile_run(c.system, run.id)
    unprivileged = Authentication.sign_in(c.system, 9, 10)

    assert {:error, :missing_capability} =
             Workflow.complete_work(
               unprivileged,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert {:ok, %{entries: []}} = Workflow.pending_work(unprivileged)

    assert_raise ForgedActorError, fn ->
      Workflow.get_run(%{c.scope | actor: %{c.scope.actor | user_id: 9}}, run.id)
    end

    retired = start!(c, idempotency_key: "retired", input: %{"retired_attempt" => true})

    assert {:error, :stale_owner_attempt} =
             Workflow.complete_work(
               c.scope,
               retired.id,
               %{step_key: "first"},
               request("example.first")
             )
  end

  test "immutable versions and missing owners retain data without execution", c do
    run = start!(c)
    [definition | rest] = TestProcessContributions.processes()
    [first | steps] = definition.steps
    install_registry!([%{definition | steps: [%{first | label: "Changed"} | steps]} | rest])

    assert {:error, :definition_version_changed} =
             Workflow.start_run(c.scope, "example.parallel", c.subject, idempotency_key: "new")

    assert {:error, :definition_unavailable} = Workflow.reconcile_run(c.scope, run.id)
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)
    assert Repo.aggregate(WorkSchema, :count) == 3
    install_registry!([])

    assert {:error, :definition_unavailable} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    install_registry!()
    assert {:ok, _} = Workflow.reconcile_run(c.scope, run.id)
  end

  test "all and any release while impossible outcomes propagate", c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.dependencies", c.subject,
               idempotency_key: "graph"
             )

    assert {:ok, _} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert {:ok, %{work_items: items}} = Workflow.get_run(c.scope, run.id)
    by_key = Map.new(items, &{&1.step_key, &1})
    assert by_key["any"].status == "available" and by_key["all"].status == "pending"
    assert by_key["impossible"].status == "blocked" and by_key["cascade"].status == "blocked"

    assert {:ok, _} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "second"},
               request("example.second")
             )

    for step <- ~w(all any),
        do:
          assert(
            {:ok, _} = Workflow.complete_work(c.scope, run.id, %{step_key: step}, request(step))
          )

    assert {:ok, %{run: %{status: "blocked", output: output}}} = Workflow.get_run(c.scope, run.id)
    assert output["first"]["outcome"] == "completed" and output["cascade"]["status"] == "blocked"
  end

  test "supersede retains completed facts and blocks unfinished work once", c do
    run = start!(c)

    assert {:ok, %{work_item: completed}} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert {:ok, %{status: "blocked"}} =
             Workflow.supersede_run(c.scope, run.id, "Owner opened another attempt")

    assert {:ok, %{work_items: items}} = Workflow.get_run(c.scope, run.id)
    assert hd(items) == completed
    assert Enum.map(items, & &1.status) == ~w(completed blocked blocked)
    assert Enum.map(items, & &1.version) == [2, 2, 2]
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)

    assert {:error, :run_not_running} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "second"},
               request("example.second")
             )

    before = events!(c.scope, run.id)
    assert List.last(before).type == "process.superseded"
    assert {:ok, _} = Workflow.supersede_run(c.scope, run.id, "Repeated")
    assert events!(c.scope, run.id) == before
    assert {:error, :reason_required} = Workflow.supersede_run(c.scope, run.id, " ")
  end

  test "live leases prevent supersede and expired leases fence stale completions", c do
    run = start!(c)

    first =
      Repo.one!(
        from(w in WorkSchema, where: w.process_run_id == ^run.id and w.step_key == "first")
      )

    time = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.update!(
      change(first,
        status: "leased",
        lease_token: "legacy-lease",
        lease_owner: "legacy-worker",
        lease_expires_at: NaiveDateTime.add(time, 60),
        attempts: 0
      )
    )

    assert {:error, :live_lease} = Workflow.supersede_run(c.scope, run.id, "Replace")

    assert {:error, :work_not_available} =
             Workflow.complete_work(c.scope, run.id, first.id, request("example.first"))

    Repo.update_all(from(w in WorkSchema, where: w.id == ^first.id),
      set: [lease_expires_at: NaiveDateTime.add(time, -1)]
    )

    assert {:ok, _} = Workflow.reconcile_run(c.scope, run.id)

    assert {:error, :stale_work} =
             Workflow.complete_work(c.scope, run.id, first.id, request("example.first"))

    assert {:ok, %{work_item: %{version: 3, status: "completed"}}} =
             Workflow.complete_work(c.scope, run.id, first.id, %{
               request("example.first")
               | expected_version: 2
             })

    assert Repo.get!(WorkSchema, first.id).lease_token == nil
  end

  test "signal and timer recover after restart and replay does not restart the timer", c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.gate", c.subject, idempotency_key: "gate")

    assert {:ok, _} =
             Workflow.signal_run(c.scope, run.id, "owner.ready", %{"fact" => true}, "fact:1")

    source_signal =
      Repo.one!(
        from(e in EventSchema,
          where: e.process_run_id == ^run.id and e.type == "signal.received"
        )
      )

    Repo.update!(
      change(source_signal, payload: Map.put(source_signal.payload, "matched_work_items", 1))
    )

    item = Repo.one!(from(w in WorkSchema, where: w.process_run_id == ^run.id))
    assert item.status == "pending" and not is_nil(item.signalled_at)
    events = events!(c.scope, run.id)

    assert {:ok, _} =
             Workflow.signal_run(c.scope, run.id, "owner.ready", %{"fact" => true}, "fact:1")

    assert {:error, :idempotency_conflict} =
             Workflow.signal_run(c.scope, run.id, "owner.ready", [], "fact:1")

    assert events!(c.scope, run.id) == events
    install_registry!()
    Repo.update!(change(item, available_at: NaiveDateTime.add(item.available_at, -120)))
    assert {:ok, _} = Workflow.reconcile_run(c.scope, run.id)
    assert {:ok, %{entries: [ready]}} = Workflow.pending_work(c.scope)
    assert ready.id == item.id

    assert {:ok, %{run: %{status: "completed"}}} =
             Workflow.complete_work(c.scope, run.id, item.id, request("fact"))
  end

  test "pending work cursors and executor filters are deterministic and respect run due time",
       c do
    run = start!(c)

    assert {:ok, %{entries: [first], next_cursor: cursor}} =
             Workflow.pending_work(c.scope, limit: 1)

    assert {:ok, %{entries: [second], next_cursor: cursor2}} =
             Workflow.pending_work(c.scope, limit: 1, after: cursor)

    assert {:ok, %{entries: [third], next_cursor: nil}} =
             Workflow.pending_work(c.scope, limit: 1, after: cursor2)

    assert [first.step_key, second.step_key, third.step_key] == ~w(first second third)

    assert {:ok, %{entries: [^second]}} =
             Workflow.pending_work(c.scope, executor_keys: ["example.second"])

    future = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(60)
    Repo.update_all(from(r in RunSchema, where: r.id == ^run.id), set: [available_at: future])
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)

    assert {:error, :work_not_due} =
             Workflow.complete_work(c.scope, run.id, first.id, request("example.first"))
  end

  test "contradictory tenant or materialized contract cannot be hidden by scoping", c do
    run = start!(c)

    Repo.update_all(
      from(w in WorkSchema, where: w.process_run_id == ^run.id and w.step_key == "first"),
      set: [tenant_id: 2]
    )

    assert {:error, :invalid_process_graph} = Workflow.reconcile_run(c.scope, run.id)
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)

    Repo.update_all(from(w in WorkSchema, where: w.process_run_id == ^run.id),
      set: [tenant_id: 1]
    )

    Repo.update_all(
      from(w in WorkSchema, where: w.process_run_id == ^run.id and w.step_key == "first"),
      set: [executor_key: "another.executor"]
    )

    assert {:error, :invalid_process_graph} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("another.executor")
             )

    assert Repo.aggregate(EventSchema, :count) == 10
  end

  test "surplus work and dependencies invalidate a saved graph instead of entering the worklist",
       c do
    run = start!(c)

    first =
      Repo.one!(
        from(w in WorkSchema, where: w.process_run_id == ^run.id, order_by: w.id, limit: 1)
      )

    attrs =
      first |> Map.from_struct() |> Map.drop([:id, :__meta__]) |> Map.put(:step_key, "extra")

    extra = %WorkSchema{} |> change(attrs) |> Repo.insert!()
    assert {:error, :invalid_process_graph} = Workflow.get_run(c.scope, run.id)
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)
    Repo.delete!(extra)

    second =
      Repo.one!(
        from(w in WorkSchema, where: w.process_run_id == ^run.id and w.step_key == "second")
      )

    %Bilimbi.Base.Workflow.DependencySchema{}
    |> change(%{
      tenant_id: 1,
      work_item_id: second.id,
      depends_on_work_item_id: first.id,
      acceptable_outcomes: ["completed"]
    })
    |> Repo.insert!()

    assert {:error, :invalid_process_graph} = Workflow.reconcile_run(c.scope, run.id)
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)
  end

  test "an event referencing another run invalidates the graph before reads or writes", c do
    run = start!(c)
    second_subject = subject!()

    assert {:ok, other} =
             Workflow.start_run(c.scope, "example.parallel", second_subject,
               idempotency_key: "other"
             )

    other_item =
      Repo.one!(
        from(w in WorkSchema, where: w.process_run_id == ^other.id, order_by: w.id, limit: 1)
      )

    event =
      Repo.one!(
        from(e in EventSchema, where: e.process_run_id == ^run.id, order_by: e.sequence, limit: 1)
      )

    Repo.update!(change(event, work_item_id: other_item.id))
    assert {:error, :invalid_process_graph} = Workflow.get_run(c.scope, run.id)
    assert {:error, :invalid_process_graph} = Workflow.reconcile_run(c.scope, run.id)
    assert {:ok, %{entries: entries}} = Workflow.pending_work(c.scope)
    assert Enum.all?(entries, &(&1.process_run_id == other.id))
  end

  test "paused and unresolved states are retained and hidden from ready work", c do
    run = start!(c)

    Repo.update_all(from(r in RunSchema, where: r.id == ^run.id),
      set: [status: "paused", pause_reason: "legacy pause"]
    )

    before = Repo.all(WorkSchema)
    assert {:ok, %{status: "paused"}} = Workflow.reconcile_run(c.scope, run.id)
    assert Repo.all(WorkSchema) == before
    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)
    Repo.update_all(from(r in RunSchema, where: r.id == ^run.id), set: [scope_type: "unresolved"])
    assert {:error, :run_not_found} = Workflow.reconcile_run(c.scope, run.id)
    assert Repo.get!(RunSchema, run.id).status == "paused"
  end

  test "an adopted paused run resumes with its original items", c do
    subject = subject!(%{id: 41})

    saved =
      Bilimbi.Base.Workflow.LegacyCoordinationFixture.insert_in_flight!(
        Repo,
        Bilimbi.Base.Database.DataCase.temporary_schema!()
      )

    Repo.update_all(from(r in RunSchema, where: r.id == ^saved.run_id),
      set: [status: "paused", paused_at: ~N[2026-01-01 00:00:00], pause_reason: "legacy pause"]
    )

    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)

    assert {:error, :run_not_running} =
             Workflow.complete_work(
               c.scope,
               saved.run_id,
               saved.items["second"],
               request("example.second")
             )

    assert {:ok, %{status: "running", pause_reason: nil, paused_at: nil}} =
             Workflow.resume_run(c.scope, saved.run_id)

    assert {:ok, %{status: "running"}} = Workflow.resume_run(c.scope, saved.run_id)
    assert {:ok, %{entries: entries}} = Workflow.pending_work(c.scope, subject: subject)

    assert Enum.map(entries, & &1.id) == [saved.items["second"], saved.items["third"]]
    assert "process.resumed" in Enum.map(events!(c.scope, saved.run_id), & &1.type)

    assert {:ok, %{status: "paused", pause_reason: "Owner hold"}} =
             Workflow.pause_run(c.scope, saved.run_id, "Owner hold")

    assert {:ok, %{status: "paused", pause_reason: "Owner hold"}} =
             Workflow.pause_run(c.scope, saved.run_id, "Second hold")

    assert {:error, :reason_required} = Workflow.pause_run(c.scope, saved.run_id, " ")
    assert {:ok, nil} = Workflow.claim_work(c.scope, "worker-1")
    assert Repo.aggregate(RunSchema, :count) == 1 and Repo.aggregate(WorkSchema, :count) == 3
  end

  test "an adopted leased item is completed by the worker holding its lease", c do
    subject!(%{id: 41})

    saved =
      Bilimbi.Base.Workflow.LegacyCoordinationFixture.insert_in_flight!(
        Repo,
        Bilimbi.Base.Database.DataCase.temporary_schema!()
      )

    token = "0b7d3f62-4c1e-4a55-9f0e-2d6c7a1b9e30"
    time = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.update_all(from(w in WorkSchema, where: w.id == ^saved.items["second"]),
      set: [
        status: "leased",
        attempts: 1,
        lease_owner: "legacy-worker",
        lease_token: token,
        lease_expires_at: NaiveDateTime.add(time, 300),
        heartbeat_at: time
      ]
    )

    claim = %{run_id: saved.run_id, work_item_id: saved.items["second"], lease_token: token}
    done = %{outcome: "completed", output: %{"worker_fact" => 9}, result_ref: nil}

    assert {:error, :lease_not_owned} =
             Workflow.complete_claimed_work(
               c.scope,
               %{claim | lease_token: "1b7d3f62-4c1e-4a55-9f0e-2d6c7a1b9e30"},
               done
             )

    assert {:error, :work_not_available} =
             Workflow.complete_work(
               c.scope,
               saved.run_id,
               saved.items["second"],
               request("example.second")
             )

    assert {:ok, %{work_item: item}} = Workflow.complete_claimed_work(c.scope, claim, done)
    assert %{status: "completed", output: %{"worker_fact" => 9}, version: 2} = item
    refute Map.has_key?(item, :lease_token)
    assert %{lease_token: nil, lease_owner: nil} = Repo.get!(WorkSchema, item.id)
    assert {:ok, %{work_item: ^item}} = Workflow.complete_claimed_work(c.scope, claim, done)

    assert {:ok, %{run: %{status: "running"}, work_items: [first, second, third]}} =
             Workflow.get_run(c.scope, saved.run_id)

    assert first.output == %{"saved_fact" => 74} and second == item
    assert third.status == "available"
  end

  test "workers claim, heartbeat, retry with backoff and finally fail", c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.retry", c.subject, idempotency_key: "retry:1")

    assert {:error, :invalid_claim} = Workflow.claim_work(c.scope, " ")
    assert {:ok, nil} = Workflow.claim_work(c.scope, "worker-1", executor_keys: [])

    assert {:ok, %{claim: claim, work_item: leased}} =
             Workflow.claim_work(c.scope, "worker-1", run_ids: [run.id], lease_seconds: 60)

    assert %{status: "leased", attempts: 1, step_key: "work"} = leased
    refute Map.has_key?(leased, :lease_token)
    assert claim.run_id == run.id and claim.work_item_id == leased.id
    assert {:ok, nil} = Workflow.claim_work(c.scope, "worker-2")

    assert {:ok, %{work_item: beat}} = Workflow.heartbeat_work(c.scope, claim, 600)
    assert NaiveDateTime.compare(beat.lease_expires_at, leased.lease_expires_at) == :gt

    assert {:error, :lease_not_owned} =
             Workflow.heartbeat_work(c.scope, %{claim | lease_token: "stale-token"})

    retry_at =
      NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(120)

    assert {:ok, %{work_item: pending}} =
             Workflow.fail_work(c.scope, claim, "Upstream timeout",
               retry_at: retry_at,
               failure_category: "transport"
             )

    assert %{status: "pending", available_at: ^retry_at, last_error: "Upstream timeout"} =
             pending

    assert {:error, :lease_not_owned} = Workflow.heartbeat_work(c.scope, claim)
    assert {:ok, nil} = Workflow.claim_work(c.scope, "worker-2")

    assert %{"failure" => %{"retryable" => true, "category" => "transport"}} =
             Enum.find(events!(c.scope, run.id), &(&1.type == "work.retry_scheduled")).payload

    Repo.update_all(from(w in WorkSchema, where: w.id == ^leased.id),
      set: [available_at: NaiveDateTime.add(retry_at, -600)]
    )

    assert {:ok, %{claim: second, work_item: %{attempts: 2}}} =
             Workflow.claim_work(c.scope, "worker-2", executor_keys: ["example.work"])

    Repo.update_all(from(w in WorkSchema, where: w.id == ^leased.id),
      set: [lease_expires_at: NaiveDateTime.add(retry_at, -600)]
    )

    assert {:error, :lease_expired} = Workflow.fail_work(c.scope, second, "Too late")

    Repo.update_all(from(w in WorkSchema, where: w.id == ^leased.id),
      set: [lease_expires_at: NaiveDateTime.add(retry_at, 600)]
    )

    assert {:ok, %{run: %{status: "failed"}, work_item: %{status: "failed", outcome: "failed"}}} =
             Workflow.fail_work(c.scope, second, "Still failing")

    assert {:ok, %{work_item: %{status: "failed"}}} =
             Workflow.complete_claimed_work(c.scope, second, %{
               outcome: "completed",
               output: [],
               result_ref: nil
             })

    assert {:ok, %{work_items: [_, %{status: "blocked"}]}} = Workflow.get_run(c.scope, run.id)
  end

  test "waive, block and claimed block finish unfinished work with reasons", c do
    run = start!(c)

    assert {:error, :reason_required} =
             Workflow.waive_work(c.scope, run.id, %{step_key: "first"}, " ")

    assert {:ok,
            %{work_item: %{status: "waived", outcome: "not-needed", last_error: "Owner skip"}}} =
             Workflow.waive_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               "Owner skip",
               "not-needed"
             )

    assert {:ok, %{work_item: %{status: "blocked", last_error: "Owner refused"}}} =
             Workflow.block_work(c.scope, run.id, %{step_key: "second"}, "Owner refused")

    assert {:ok, %{work_item: %{status: "waived"}}} =
             Workflow.block_work(c.scope, run.id, %{step_key: "first"}, "Too late")

    assert {:ok, %{claim: claim}} =
             Workflow.claim_work(c.scope, "worker-1", executor_keys: ["example.third"])

    assert {:ok, %{run: %{status: "blocked"}, work_item: blocked}} =
             Workflow.block_claimed_work(c.scope, claim, "Bad input",
               output: %{"diagnostic" => 1},
               result_ref: "owner-result:9"
             )

    assert %{status: "blocked", output: %{"diagnostic" => 1}, result_ref: "owner-result:9"} =
             blocked

    types = Enum.map(events!(c.scope, run.id), & &1.type)
    assert Enum.all?(~w(work.waived work.blocked work.claimed process.blocked), &(&1 in types))
    assert {:error, :run_not_paused} = Workflow.resume_run(c.scope, run.id)
    assert {:error, :run_not_running} = Workflow.pause_run(c.scope, run.id, "Hold")
  end

  test "reconcile clears a retained definition-unavailable mark once the definition is proved",
       c do
    subject = subject!(%{id: 41})

    saved =
      Bilimbi.Base.Workflow.LegacyCoordinationFixture.insert_in_flight!(
        Repo,
        Bilimbi.Base.Database.DataCase.temporary_schema!()
      )

    Repo.update_all(from(r in RunSchema, where: r.id == ^saved.run_id),
      set: [last_error: "Process definition cannot be reconciled: definition missing"]
    )

    assert {:ok, %{entries: []}} = Workflow.pending_work(c.scope)

    assert {:error, :run_unavailable} =
             Workflow.complete_work(
               c.scope,
               saved.run_id,
               saved.items["second"],
               request("example.second")
             )

    assert {:ok, %{status: "running", last_error: nil}} =
             Workflow.reconcile_run(c.scope, saved.run_id)

    assert %{"definition_key" => "example.parallel", "definition_version" => 1} =
             Enum.find(
               events!(c.scope, saved.run_id),
               &(&1.type == "process.definition_restored")
             ).payload

    assert {:ok, %{entries: entries}} = Workflow.pending_work(c.scope, subject: subject)
    assert Enum.map(entries, & &1.id) == [saved.items["second"], saved.items["third"]]

    Repo.update_all(from(r in RunSchema, where: r.id == ^saved.run_id),
      set: [last_error: "Owner diagnostic"]
    )

    assert {:ok, %{last_error: "Owner diagnostic"}} =
             Workflow.reconcile_run(c.scope, saved.run_id)
  end

  test "duplicate acceptable outcomes fingerprint raw but save and compare unique edges", c do
    duplicate = %{
      key: "example.duplicate",
      version: 1,
      subject: "example.record",
      adapter: Bilimbi.Base.Workflow.TestProcessAdapter,
      steps: [
        %{key: "first", label: "First", executor_key: "example.first"},
        %{
          key: "second",
          label: "Second",
          dependencies: [%{step_key: "first", acceptable_outcomes: ["completed", "completed"]}]
        }
      ]
    }

    install_registry!([duplicate])
    installed = Bilimbi.Base.Workflow.Definitions.registry!().processes[{"example.duplicate", 1}]

    unique =
      update_in(installed, [:steps, Access.at(1), :dependencies, Access.at(0)], fn dependency ->
        %{dependency | acceptable_outcomes: ["completed"]}
      end)

    refute installed.fingerprint == Bilimbi.Base.Workflow.ProcessFingerprint.digest(unique)

    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.duplicate", c.subject, idempotency_key: "dup")

    assert run.definition_fingerprint == installed.fingerprint
    assert [["completed"]] = Repo.all(from(d in DependencySchema, select: d.acceptable_outcomes))
    assert {:ok, %{work_items: [_, _]}} = Workflow.get_run(c.scope, run.id)

    assert {:ok, %{run: %{status: "running"}}} =
             Workflow.complete_work(
               c.scope,
               run.id,
               %{step_key: "first"},
               request("example.first")
             )

    assert {:ok, %{work_items: [_, %{status: "available"}]}} = Workflow.get_run(c.scope, run.id)
  end

  test "uninstalled and owner-refused runs do not starve supported claims", c do
    time = ~N[2026-01-01 00:00:00]

    [retired] =
      Repo.insert_all(
        RunSchema,
        [
          %{
            definition_key: "example.retired",
            definition_version: 3,
            definition_fingerprint: String.duplicate("a", 64),
            status: "running",
            subject_type: "example.record",
            subject_id: to_string(c.subject.id),
            input: [],
            started_at: time,
            available_at: time,
            scope_type: "tenant",
            tenant_id: 1
          }
        ],
        returning: [:id]
      )
      |> elem(1)

    Repo.insert_all(
      WorkSchema,
      for index <- 1..9 do
        %{
          process_run_id: retired.id,
          step_key: "retained-#{index}",
          label: "Retained",
          executor_key: "example.retained",
          status: "available",
          available_at: time,
          input: [],
          metadata: [],
          tenant_id: 1,
          version: 1
        }
      end
    )

    refused =
      for index <- 1..3 do
        private = subject!()

        assert {:ok, _} =
                 Workflow.start_run(c.scope, "example.parallel", private,
                   idempotency_key: "refused:#{index}"
                 )

        private.id
      end

    Repo.update_all(from(s in Bilimbi.Base.Workflow.TestSubjectSchema, where: s.id in ^refused),
      set: [marker: "process_private"]
    )

    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.parallel", c.subject, idempotency_key: "served")

    assert {:ok, %{claim: %{run_id: run_id}, work_item: %{step_key: "first"}}} =
             Workflow.claim_work(c.scope, "worker-1")

    assert run_id == run.id

    assert Repo.aggregate(from(w in WorkSchema, where: w.process_run_id == ^retired.id), :count) ==
             9

    assert Repo.get!(RunSchema, retired.id).status == "running"
  end

  defp start!(c, opts \\ []) do
    assert {:ok, run} =
             Workflow.start_run(
               c.scope,
               "example.parallel",
               c.subject,
               Keyword.merge([idempotency_key: "attempt:1"], opts)
             )

    run
  end

  defp request(executor),
    do: %{
      expected_version: 1,
      executor_key: executor,
      outcome: "completed",
      output: %{"fact" => true},
      result_ref: "owner-result:1"
    }

  defp events!(scope, id) do
    assert {:ok, %{entries: events}} = Workflow.run_events(scope, id, limit: 500)
    events
  end
end
