defmodule Bilimbi.Base.Workflow.CoordinationConcurrencyTest do
  use ExUnit.Case, async: false
  alias Bilimbi.Base.{Authz, Repo, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Ecto.Adapters.SQL
  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    schema =
      "workflow_coord_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      SQL.query!(Repo, ~s(CREATE SCHEMA "#{schema}"), [])
    end)

    on_exit(fn ->
      ContributionRegistry.clear_for_test!()

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, ~s(DROP SCHEMA "#{schema}" CASCADE), [])
      end)
    end)

    name = :workflow_coordination_repo

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

    %{name: name, options: options, scope: scope, subject: subject!(), schema: schema}
  end

  test "three connections racing complete three lanes and emit one terminal run event", c do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.parallel", c.subject, idempotency_key: "race")

    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    first =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.name)

        Repo.transact(fn ->
          Repo.query!("SELECT id FROM workflow_test_subjects WHERE id = $1 FOR UPDATE", [
            c.subject.id
          ])

          send(parent, {:locked, self()})

          receive do
            :complete ->
              Workflow.complete_work(c.scope, run.id, %{step_key: "first"}, request("first"))
          after
            5_000 -> raise "completion barrier timed out"
          end
        end)
      end)

    assert_receive {:locked, holder}, 5_000

    contenders =
      for key <- ~w(second third) do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(c.name)

          Repo.transact(fn ->
            [[pid]] = Repo.query!("SELECT pg_backend_pid()", []).rows
            send(parent, {:contender, pid})
            Workflow.complete_work(c.scope, run.id, %{step_key: key}, request(key))
          end)
        end)
      end

    for _ <- 1..2 do
      assert_receive {:contender, backend}, 5_000
      await_lock!(backend, System.monotonic_time(:millisecond) + 5_000)
    end

    send(holder, :complete)
    results = Task.await_many([first | contenders], 15_000)

    assert Enum.all?(
             results,
             &match?({:ok, %{work_item: %{status: "completed", version: 2}}}, &1)
           )

    assert {:ok, %{run: %{status: "completed", output: output}, work_items: items}} =
             Workflow.get_run(c.scope, run.id)

    assert Map.keys(output) |> Enum.sort() == ~w(first second third)
    assert Enum.all?(items, &(&1.output == %{"fact" => &1.step_key}))
    assert {:ok, %{entries: events}} = Workflow.run_events(c.scope, run.id, limit: 500)
    assert Enum.map(events, & &1.sequence) == Enum.to_list(1..14)
    assert Enum.count(events, &(&1.type == "process.completed")) == 1
    assert Enum.count(events, &(&1.type == "work.completed")) == 3
    assert :ok = Bilimbi.Base.Workflow.SchemaContract.verify_invariants(c.name, prefix: c.schema)
  end

  test "a new owner process and reconnected Repo recover persisted work without rematerializing",
       c do
    supervisor = start_supervised!(Task.Supervisor)

    opening =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.name)

        assert {:ok, run} =
                 Workflow.start_run(c.scope, "example.parallel", c.subject,
                   idempotency_key: "restart",
                   input: %{"carried_fact_ids" => %{"earlier" => 42}}
                 )

        assert {:ok, %{work_item: completed}} =
                 Workflow.complete_work(c.scope, run.id, %{step_key: "first"}, request("first"))

        {run, completed}
      end)

    {run, completed} = Task.await(opening)
    assert :ok = stop_supervised(c.name)
    start_supervised!(Supervisor.child_spec({Repo, c.options}, id: c.name))
    install_registry!()

    recovering =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.name)
        assert {:ok, resumed} = Workflow.reconcile_run(c.scope, run.id)
        assert resumed.id == run.id and resumed.input == run.input
        Workflow.get_run(c.scope, run.id)
      end)

    assert {:ok, %{work_items: items}} = Task.await(recovering)
    assert hd(items) == completed
    assert Enum.map(items, & &1.status) == ~w(completed available available)
    assert {:ok, %{entries: pending}} = Workflow.pending_work(c.scope)
    assert Enum.map(pending, & &1.id) == Enum.map(tl(items), & &1.id)

    assert [[1, 3]] =
             Repo.query!(
               "SELECT (SELECT count(*) FROM base_workflow_process_runs), (SELECT count(*) FROM base_workflow_process_work_items)",
               []
             ).rows
  end

  defp request(key),
    do: %{
      expected_version: 1,
      executor_key: "example." <> key,
      outcome: "completed",
      output: %{"fact" => key},
      result_ref: "owner-result:" <> key
    }

  defp await_lock!(backend, deadline) do
    case Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend]).rows do
      [["Lock"]] ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: raise("completion did not contend on the owner lock")

        await_lock!(backend, deadline)
    end
  end
end
