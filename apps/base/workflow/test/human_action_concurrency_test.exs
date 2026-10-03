defmodule Bilimbi.Base.Workflow.HumanActionConcurrencyTest do
  use ExUnit.Case, async: false
  alias Bilimbi.Base.{Authz, Repo, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Ecto.Adapters.SQL
  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    schema =
      "workflow_human_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      SQL.query!(Repo, ~s(CREATE SCHEMA "#{schema}"), [])
    end)

    on_exit(fn ->
      ContributionRegistry.clear_for_test!()

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, ~s(DROP SCHEMA "#{schema}" CASCADE), [])
      end)
    end)

    name = :workflow_human_action_repo

    options = [
      name: name,
      pool: DBConnection.ConnectionPool,
      pool_size: 4,
      parameters: [search_path: schema]
    ]

    start_supervised!(Supervisor.child_spec({Repo, options}, id: name))
    previous = Repo.put_dynamic_repo(name)
    on_exit(fn -> Repo.put_dynamic_repo(previous) end)

    paths =
      for owner <- ~w(tenancy audit authz workflow),
          do: Path.expand("../../#{owner}/priv/repo/migrations", __DIR__)

    Ecto.Migrator.run(Repo, paths, :up, all: true, prefix: schema, log: false)

    assert :ok =
             Bilimbi.Base.Database.SchemaVerifier.verify(
               name,
               Bilimbi.Base.Workflow.SchemaContract.tables(),
               prefix: schema
             )

    assert :ok = Bilimbi.Base.Workflow.SchemaContract.verify_invariants(name, prefix: schema)

    assert {:ok, _} =
             Bilimbi.Base.Tenancy.create_tenant(%{name: "Example tenant", status: "active"})

    Repo.query!(
      "CREATE TABLE workflow_test_subjects (id bigserial PRIMARY KEY, tenant_id bigint NOT NULL, company_id bigint, status varchar(255), marker varchar(255))",
      []
    )

    install_registry!()
    system = Bilimbi.Base.Authz.TestFixtures.scope()
    scope = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(system, 10, :user, 7, "admin.test.record.view", true)

    %{name: name, scope: scope, subject: subject!(), schema: schema}
  end

  test "duplicate submissions execute once; the loser replays and a changed intent conflicts",
       c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.parallel", c.subject, idempotency_key: "race")

    assert {:ok, %{subject_version: version, actions: actions}} =
             Workflow.available_actions(c.scope, c.subject)

    first = Enum.find(actions, &(&1.key == "example.first"))

    request = %{
      action_key: "example.first",
      idempotency_key: "race:first",
      expected_subject_version: version,
      payload: %{"score" => "9"},
      process_run_id: first.process_run_id,
      work_item_id: first.work_item_id,
      expected_work_version: first.work_version
    }

    results = race(c, [request, request])

    assert [{:ok, executed}, {:ok, replayed}] =
             Enum.sort_by(results, fn {:ok, r} -> r.replayed end)

    assert executed.replayed == false and replayed.replayed == true
    assert Map.delete(executed, :replayed) == Map.delete(replayed, :replayed)

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM base_workflow_human_action_requests", []).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM base_audit_actions WHERE event = 'workflow.human_action.completed'",
               []
             ).rows

    assert {:ok, %{work_items: [%{status: "completed", version: 2} | _]}} =
             Workflow.get_run(c.scope, run.id)

    assert {:ok, %{entries: events}} = Workflow.run_events(c.scope, run.id, limit: 500)
    assert Enum.count(events, &(&1.type == "work.completed")) == 1
    assert state(c.subject.id).marker == "human:example.first"

    assert {:ok, %{subject_version: version}} = Workflow.available_actions(c.scope, c.subject)

    approve = %{
      action_key: "example.approve",
      idempotency_key: "race:approve",
      expected_subject_version: version,
      payload: %{"n" => 1}
    }

    results = race(c, [approve, %{approve | payload: %{"n" => 2}}])
    assert Enum.sort(results, :desc) |> Enum.map(&elem(&1, 0)) == [:ok, :error]
    assert {:error, :idempotency_conflict} = Enum.find(results, &match?({:error, _}, &1))

    assert [[2]] =
             Repo.query!("SELECT count(*) FROM base_workflow_human_action_requests", []).rows

    assert :ok = Bilimbi.Base.Workflow.SchemaContract.verify_invariants(c.name, prefix: c.schema)
  end

  test "verification refuses a retained request whose completion and result disagree", c do
    Repo.query!(
      """
      INSERT INTO base_workflow_human_action_requests
        (tenant_id, idempotency_key, intent_hash, action_key, subject_type, subject_id, actor_type, actor_id, completed_at)
      VALUES (1, 'torn', $1, 'example.approve', 'Legacy\\Example\\Record', '41', 'user', 7, '2026-01-01')
      """,
      [String.duplicate("e", 64)]
    )

    assert {:error, [error]} =
             Bilimbi.Base.Workflow.SchemaContract.verify_invariants(c.name, prefix: c.schema)

    assert error =~ "human request completion and result disagree"
  end

  # One connection holds the owner row until both contenders wait on it, so
  # the submissions enter the gate together and are ordered only by the lock.
  defp race(c, requests) do
    supervisor = start_supervised!(Task.Supervisor, id: make_ref())
    parent = self()

    holder =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.name)

        Repo.transact(fn ->
          Repo.query!("SELECT id FROM workflow_test_subjects WHERE id = $1 FOR UPDATE", [
            c.subject.id
          ])

          send(parent, {:locked, self()})

          receive do
            :release -> {:ok, :released}
          after
            10_000 -> raise "race barrier timed out"
          end
        end)
      end)

    assert_receive {:locked, locker}, 5_000

    contenders =
      for request <- requests do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(c.name)

          # The surrounding transaction pins one connection, so the reported
          # backend is the one that waits; the gate's own transaction nests.
          Repo.transact(fn ->
            [[pid]] = Repo.query!("SELECT pg_backend_pid()", []).rows
            send(parent, {:contender, pid})
            Workflow.execute_action(c.scope, c.subject, request)
          end)
        end)
      end

    for _ <- requests do
      assert_receive {:contender, backend}, 5_000

      await_lock!(backend, System.monotonic_time(:millisecond) + 5_000)
    end

    send(locker, :release)
    assert {:ok, :released} = Task.await(holder, 5_000)
    Task.await_many(contenders, 15_000)
  end

  defp await_lock!(backend, deadline) do
    case Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend]).rows do
      [["Lock"]] ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: raise("submission did not contend on the owner lock")

        await_lock!(backend, deadline)
    end
  end
end
