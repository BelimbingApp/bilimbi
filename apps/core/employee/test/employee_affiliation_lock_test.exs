defmodule Bilimbi.Core.Employee.AffiliationLockTest do
  @moduledoc false

  # async: false — the lock contract needs independent PostgreSQL connections
  # that can deterministically observe each other's row-lock waits.
  use ExUnit.Case, async: false

  import Bilimbi.Base.Database.LockSchema

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.AffiliationProof
  alias Bilimbi.Core.Employee.Schema
  alias Bilimbi.Core.Employee.TestFixtures, as: EmployeeFixtures
  alias Ecto.Adapters.SQL

  setup do
    schema = create!("employee_affiliation_lock")

    scopes =
      on_schema!(schema, fn ->
        TenancyFixtures.create_tenants_table!(persistent: true)
        CompanyFixtures.create_companies_table!(persistent: true)
        EmployeeFixtures.create_employees_table!(persistent: true)
        seed!()
        {:ok, owner_scope} = Tenancy.scope(41)
        {:ok, foreign_scope} = Tenancy.scope(42)
        %{owner: owner_scope, foreign: foreign_scope}
      end)

    %{schema: schema, owner_scope: scopes.owner, foreign_scope: scopes.foreign}
  end

  test "requires the caller's existing shared Repo transaction", %{
    schema: schema,
    owner_scope: scope
  } do
    on_schema!(schema, fn ->
      refute Repo.in_transaction?()
      assert {:error, :transaction_required} = Employee.lock_affiliation(scope, 73, 101)
      assert {:error, :transaction_required} = Employee.lock_affiliation(scope, 0, 0)

      assert {:ok, {:ok, %AffiliationProof{id: 101, company_id: 73}}} =
               Repo.transaction(fn ->
                 assert Repo.in_transaction?()
                 Employee.lock_affiliation(scope, 73, 101)
               end)
    end)
  end

  test "returns a schema-free proof and does not invent employee status liveness", %{
    schema: schema,
    owner_scope: scope
  } do
    on_schema!(schema, fn ->
      assert {:ok, {:ok, %AffiliationProof{} = proof}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)

      assert Map.from_struct(proof) == %{id: 101, company_id: 73}
      refute is_struct(proof, Schema)
      refute Map.has_key?(proof, :__meta__)
      assert Ecto.Queryable.impl_for(proof) == nil

      assert {:ok, {:ok, %AffiliationProof{id: 104, company_id: 73}}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 104) end)
    end)
  end

  test "collapses malformed, missing, cross-tenant, and company-mismatched identities", %{
    schema: schema,
    owner_scope: owner_scope,
    foreign_scope: foreign_scope
  } do
    on_schema!(schema, fn ->
      misses = [
        {0, 101},
        {-1, 101},
        {nil, 101},
        {"73", 101},
        {73, 0},
        {73, -1},
        {73, nil},
        {73, "101"},
        {73, 999},
        {73, 102},
        {73, 103},
        {74, 102},
        {75, 101},
        {999, 101}
      ]

      for {company_id, employee_id} <- misses do
        assert {:ok, {:error, :not_found}} =
                 Repo.transaction(fn ->
                   Employee.lock_affiliation(owner_scope, company_id, employee_id)
                 end)
      end

      assert {:ok, {:ok, %AffiliationProof{id: 102, company_id: 74}}} =
               Repo.transaction(fn -> Employee.lock_affiliation(foreign_scope, 74, 102) end)
    end)
  end

  test "rejects a malformed scope at the public boundary", %{schema: schema} do
    on_schema!(schema, fn ->
      assert_raise FunctionClauseError, fn ->
        Repo.transaction(fn -> apply(Employee, :lock_affiliation, [41, 73, 101]) end)
      end
    end)
  end

  test "rollback releases the transaction-bound proof locks", %{
    schema: schema,
    owner_scope: scope
  } do
    on_schema!(schema, fn ->
      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 assert {:ok, %AffiliationProof{id: 101}} =
                          Employee.lock_affiliation(scope, 73, 101)

                 Repo.rollback(:rollback)
               end)

      assert {:ok, {:ok, %AffiliationProof{id: 101, company_id: 73}}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)
    end)
  end

  test "the affiliation proof retains its employee row lock until commit", %{
    schema: schema,
    owner_scope: scope
  } do
    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            assert {:ok, %AffiliationProof{id: 101}} =
                     Employee.lock_affiliation(scope, 73, 101)

            send(parent, :employee_lock_holder_ready)
            await_message!(:commit_employee_lock_holder)
          end)
        end)
      end)

    assert_receive :employee_lock_holder_ready, 5_000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          backend_pid = backend_pid!()
          send(parent, {:employee_update_backend, backend_pid})

          SQL.query!(
            Repo,
            "UPDATE employees SET designation = 'Updated after lock' WHERE id = 101",
            []
          )
        end)
      end)

    assert_receive {:employee_update_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :commit_employee_lock_holder)

    assert {:ok, :ok} = Task.await(holder, 5_000)
    assert %{num_rows: 1} = Task.await(contender, 5_000)
  end

  test "two sibling writers serialize on the same affiliation until commit", %{
    schema: schema,
    owner_scope: scope
  } do
    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            assert {:ok, %AffiliationProof{id: 101}} =
                     Employee.lock_affiliation(scope, 73, 101)

            send(parent, :affiliation_holder_locked)
            await_message!(:commit_affiliation_holder)
          end)
        end)
      end)

    assert_receive :affiliation_holder_locked, 5_000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          backend_pid = backend_pid!()
          send(parent, {:affiliation_contender_backend, backend_pid})
          Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)
        end)
      end)

    assert_receive {:affiliation_contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :commit_affiliation_holder)

    assert {:ok, :ok} = Task.await(holder, 5_000)

    assert {:ok, {:ok, %AffiliationProof{id: 101, company_id: 73}}} =
             Task.await(contender, 5_000)
  end

  test "a waiting proof rechecks the employee company after a concurrent move", %{
    schema: schema,
    owner_scope: scope
  } do
    parent = self()

    holder =
      start_employee_change_holder(schema, parent, :move_holder_locked, :move_and_commit, fn ->
        SQL.query!(Repo, "UPDATE employees SET company_id = 76 WHERE id = 101", [])
      end)

    assert_receive :move_holder_locked, 5_000
    contender = start_proof_contender(schema, scope, parent, :move_contender_backend)
    assert_receive {:move_contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :move_and_commit)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end

  test "a waiting proof rechecks after a concurrent employee hard delete", %{
    schema: schema,
    owner_scope: scope
  } do
    parent = self()

    holder =
      start_employee_change_holder(
        schema,
        parent,
        :delete_holder_locked,
        :delete_and_commit,
        fn -> SQL.query!(Repo, "DELETE FROM employees WHERE id = 101", []) end
      )

    assert_receive :delete_holder_locked, 5_000
    contender = start_proof_contender(schema, scope, parent, :delete_contender_backend)
    assert_receive {:delete_contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :delete_and_commit)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end

  test "only the protected SYS-001 agent pair is an invariant error", %{
    schema: schema,
    owner_scope: scope
  } do
    on_schema!(schema, fn ->
      assert {:ok, {:error, :invariant_violation}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 76, 105) end)

      assert {:ok, {:ok, %AffiliationProof{id: 101}}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)

      assert {:ok, {:ok, %AffiliationProof{id: 106, company_id: 73} = proof}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 106) end)

      assert Map.from_struct(proof) == %{id: 106, company_id: 73}
      refute is_struct(proof, Schema)
      refute Map.has_key?(proof, :__meta__)
      assert Ecto.Queryable.impl_for(proof) == nil

      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 76, 999) end)
    end)
  end

  test "orchestrator protection is decided from the locked row after a wait", %{
    schema: schema,
    owner_scope: scope
  } do
    parent = self()

    holder =
      start_employee_change_holder(
        schema,
        parent,
        :orchestrator_holder_locked,
        :rewrite_and_commit,
        fn ->
          # Production keeps (company_id, employee_number) unique, so the legacy
          # row that holds SYS-001 in this company gives the number up first.
          SQL.query!(Repo, "UPDATE employees SET employee_number = 'EMP-106' WHERE id = 106", [])

          SQL.query!(
            Repo,
            "UPDATE employees SET employee_number = 'SYS-001', employee_type = 'agent' WHERE id = 101",
            []
          )
        end
      )

    assert_receive :orchestrator_holder_locked, 5_000
    contender = start_proof_contender(schema, scope, parent, :orchestrator_contender_backend)
    assert_receive {:orchestrator_contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :rewrite_and_commit)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :invariant_violation}} = Task.await(contender, 5_000)
  end

  test "the composed proof rechecks a live company after a competing soft delete", %{
    schema: schema,
    owner_scope: scope
  } do
    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            %{rows: [[73]]} =
              SQL.query!(Repo, "SELECT id FROM companies WHERE id = 73 FOR UPDATE", [])

            send(parent, :company_holder_locked)
            await_message!(:soft_delete_company)

            SQL.query!(
              Repo,
              "UPDATE companies SET deleted_at = '2026-08-14 00:00:00' WHERE id = 73",
              []
            )
          end)
        end)
      end)

    assert_receive :company_holder_locked, 5_000
    contender = start_proof_contender(schema, scope, parent, :company_contender_backend)
    assert_receive {:company_contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :soft_delete_company)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end

  defp start_employee_change_holder(schema, parent, locked_message, release_message, change) do
    Task.async(fn ->
      checkout_on_schema!(schema, fn ->
        Repo.transaction(fn ->
          %{rows: [[101]]} =
            SQL.query!(Repo, "SELECT id FROM employees WHERE id = 101 FOR UPDATE", [])

          send(parent, locked_message)
          await_message!(release_message)
          change.()
        end)
      end)
    end)
  end

  defp start_proof_contender(schema, scope, parent, backend_message) do
    Task.async(fn ->
      checkout_on_schema!(schema, fn ->
        backend_pid = backend_pid!()
        send(parent, {backend_message, backend_pid})
        Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)
      end)
    end)
  end

  defp seed! do
    TenancyFixtures.insert_tenant!(%{id: 41, name: "Owner"})
    TenancyFixtures.insert_tenant!(%{id: 42, name: "Other", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Live", code: "live"})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 42, name: "Foreign", code: "foreign"})

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 41,
      name: "Deleted",
      code: "deleted",
      deleted_at: ~N[2026-08-13 00:00:00]
    })

    CompanyFixtures.insert_company!(%{id: 76, tenant_id: 41, name: "Second", code: "second"})

    SQL.query!(
      Repo,
      """
      INSERT INTO employees
        (id, company_id, employee_number, full_name, employee_type, status)
      VALUES
        (101, 73, 'EMP-101', 'Ordinary Employee', 'full_time', 'active'),
        (102, 74, 'EMP-102', 'Foreign Employee', 'full_time', 'active'),
        (103, 76, 'EMP-103', 'Other Company Employee', 'full_time', 'active'),
        (104, 73, 'EMP-104', 'Terminated Employee', 'full_time', 'terminated'),
        (105, 76, 'SYS-001', 'Protected Orchestrator', 'agent', 'active'),
        (106, 73, 'SYS-001', 'Legacy Non-Agent', 'full_time', 'active')
      """,
      []
    )
  end
end
