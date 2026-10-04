defmodule Bilimbi.Base.Workflow.ConcurrencyTest do
  use ExUnit.Case, async: false
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Base.{Authz, Repo, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Ecto.Adapters.SQL
  import Bilimbi.Base.Workflow.TestFixtures

  test "competing connections reread the locked owner status before selecting an edge" do
    schema =
      "workflow_lock_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      SQL.query!(Repo, ~s(CREATE SCHEMA "#{schema}"), [])
    end)

    on_exit(fn ->
      ContributionRegistry.clear_for_test!()

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, ~s(DROP SCHEMA "#{schema}" CASCADE), [])
      end)
    end)

    repo_name = :workflow_concurrency_repo

    start_supervised!(
      {Repo,
       name: repo_name,
       pool: DBConnection.ConnectionPool,
       pool_size: 4,
       parameters: [search_path: schema]}
    )

    previous = Repo.put_dynamic_repo(repo_name)

    try do
      # Each dependency owns its DDL; real separate pool connections share this
      # disposable schema instead of a sandbox's shared single connection.
      paths =
        for owner <- ~w(tenancy audit authz workflow),
            do: Path.expand("../../#{owner}/priv/repo/migrations", __DIR__)

      Ecto.Migrator.run(Repo, paths, :up, all: true, prefix: schema, log: false)

      assert {:ok, %{id: 1}} =
               Bilimbi.Base.Tenancy.create_tenant(%{name: "Example tenant", status: "active"})

      Repo.query!(
        """
        CREATE TABLE workflow_test_subjects (
          id bigserial PRIMARY KEY, tenant_id bigint NOT NULL, company_id bigint,
          status varchar(255), marker varchar(255)
        )
        """,
        []
      )

      install_registry!()
      system = TenancyFixtures.scope()
      scope = Authentication.sign_in(system, 7, 10)

      assert {:ok, :stored} =
               Authz.put_principal_capability(
                 system,
                 10,
                 :user,
                 7,
                 "admin.test.record.view",
                 true
               )

      assert {:ok, :seeded} = Workflow.seed_definitions()
      subject = subject!()
      parent = self()
      supervisor = start_supervised!(Task.Supervisor)

      first =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(repo_name)

          Repo.transact(fn ->
            Repo.query!("SELECT id FROM workflow_test_subjects WHERE id = $1 FOR UPDATE", [
              subject.id
            ])

            send(parent, {:owner_locked, self()})

            receive do
              :commit -> Workflow.transition(scope, subject, "review")
            after
              5_000 -> raise "lock barrier timed out"
            end
          end)
        end)

      assert_receive {:owner_locked, holder}, 5_000

      second =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(repo_name)
          # The connection is checked out before announcing the contender.
          Repo.transact(fn ->
            [[pid]] = Repo.query!("SELECT pg_backend_pid()", []).rows
            send(parent, {:contending, pid})
            Workflow.transition(scope, subject, "closed")
          end)
        end)

      assert_receive {:contending, backend}, 5_000
      await_lock!(backend, System.monotonic_time(:millisecond) + 5_000)
      send(holder, :commit)
      assert {:ok, %{to: "review"}} = Task.await(first, 10_000)
      assert {:error, :invalid_edge} = Task.await(second, 10_000)
      assert state(subject.id).status == "review"
      assert [[1]] = Repo.query!("SELECT count(*) FROM base_workflow_status_history", []).rows

      assert [[1]] =
               Repo.query!(
                 "SELECT count(*) FROM base_audit_actions WHERE event = 'workflow.transition.completed'",
                 []
               ).rows
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp await_lock!(backend, deadline) do
    case Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend]).rows do
      [["Lock"]] ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: raise("contender did not block on owner lock")

        await_lock!(backend, deadline)
    end
  end
end
