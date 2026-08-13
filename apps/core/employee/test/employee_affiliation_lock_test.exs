defmodule Bilimbi.Core.Employee.AffiliationLockTest do
  @moduledoc false

  # async: false — the lock contract needs independent PostgreSQL connections
  # that can deterministically observe each other's row-lock waits.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.AffiliationProof
  alias Bilimbi.Core.Employee.Schema
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    schema = "employee_affiliation_lock_#{System.unique_integer([:positive])}"
    create_lock_schema!(schema)
    on_exit(fn -> drop_lock_schema!(schema) end)

    scopes =
      on_schema!(schema, fn ->
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
        checkout_and_on_schema!(schema, fn ->
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
        checkout_and_on_schema!(schema, fn ->
          backend_pid = current_backend_pid!()
          send(parent, {:employee_update_backend, backend_pid})

          SQL.query!(
            Repo,
            "UPDATE employees SET designation = 'Updated after lock' WHERE id = 101",
            []
          )
        end)
      end)

    assert_receive {:employee_update_backend, backend_pid}, 5_000
    await_backend_lock_wait!(backend_pid)
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
        checkout_and_on_schema!(schema, fn ->
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
        checkout_and_on_schema!(schema, fn ->
          backend_pid = current_backend_pid!()
          send(parent, {:affiliation_contender_backend, backend_pid})
          Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)
        end)
      end)

    assert_receive {:affiliation_contender_backend, backend_pid}, 5_000
    await_backend_lock_wait!(backend_pid)
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
    await_backend_lock_wait!(backend_pid)
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
    await_backend_lock_wait!(backend_pid)
    send(holder.pid, :delete_and_commit)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end

  test "the protected platform orchestrator is the only invariant error", %{
    schema: schema,
    owner_scope: scope
  } do
    on_schema!(schema, fn ->
      assert {:ok, {:error, :invariant_violation}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 76, 105) end)

      assert {:ok, {:ok, %AffiliationProof{id: 101}}} =
               Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)

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
    await_backend_lock_wait!(backend_pid)
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
        checkout_and_on_schema!(schema, fn ->
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
    await_backend_lock_wait!(backend_pid)
    send(holder.pid, :soft_delete_company)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end

  defp start_employee_change_holder(schema, parent, locked_message, release_message, change) do
    Task.async(fn ->
      checkout_and_on_schema!(schema, fn ->
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
      checkout_and_on_schema!(schema, fn ->
        backend_pid = current_backend_pid!()
        send(parent, {backend_message, backend_pid})
        Repo.transaction(fn -> Employee.lock_affiliation(scope, 73, 101) end)
      end)
    end)
  end

  defp current_backend_pid! do
    %{rows: [[backend_pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
    backend_pid
  end

  defp await_message!(message) do
    receive do
      ^message -> :ok
    after
      5_000 -> Repo.rollback({:timeout, message})
    end
  end

  defp await_backend_lock_wait!(backend_pid), do: await_backend_lock_wait!(backend_pid, 50)

  defp await_backend_lock_wait!(_backend_pid, 0) do
    flunk("contender never waited on a row lock")
  end

  defp await_backend_lock_wait!(backend_pid, remaining) do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [
        backend_pid
      ])

    case rows do
      [["Lock"]] ->
        :ok

      _other ->
        receive do
        after
          20 -> await_backend_lock_wait!(backend_pid, remaining - 1)
        end
    end
  end

  defp checkout_and_on_schema!(schema, fun) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    on_schema!(schema, fun)
  end

  defp on_schema!(schema, fun) do
    SQL.query!(Repo, "SET search_path TO #{quote_ident(schema)}", [])

    try do
      fun.()
    after
      SQL.query!(Repo, "SET search_path TO public", [])
    end
  end

  defp create_lock_schema!(schema) do
    quoted_schema = quote_ident(schema)
    SQL.query!(Repo, "CREATE SCHEMA #{quoted_schema}", [])

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{quoted_schema}.tenants (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        name varchar(255) NOT NULL,
        status varchar(255) NOT NULL DEFAULT 'active',
        is_platform_operator boolean NOT NULL DEFAULT false,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{quoted_schema}.companies (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        tenant_id bigint NOT NULL,
        name varchar(255) NOT NULL,
        code varchar(255) NOT NULL UNIQUE,
        status varchar(255) NOT NULL DEFAULT 'active',
        legal_name varchar(255),
        registration_number varchar(255),
        tax_id varchar(255),
        legal_entity_type_id bigint,
        jurisdiction varchar(255),
        email varchar(255),
        website varchar(255),
        scope_activities json,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{quoted_schema}.employees (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        department_id bigint,
        supervisor_id bigint,
        employee_number varchar(255) NOT NULL,
        full_name varchar(255) NOT NULL,
        short_name varchar(255),
        designation varchar(255),
        employee_type varchar(255) NOT NULL DEFAULT 'full_time',
        job_description text,
        email varchar(255),
        mobile_number varchar(255),
        status varchar(255) NOT NULL DEFAULT 'active',
        employment_start date,
        employment_end date,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{quoted_schema}.tenants (id, name, status, is_platform_operator)
      VALUES (41, 'Owner', 'active', true), (42, 'Other', 'active', false)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{quoted_schema}.companies (id, tenant_id, name, code, status, deleted_at)
      VALUES
        (73, 41, 'Live', 'live', 'active', NULL),
        (74, 42, 'Foreign', 'foreign', 'active', NULL),
        (75, 41, 'Deleted', 'deleted', 'active', '2026-08-13 00:00:00'),
        (76, 41, 'Second', 'second', 'active', NULL)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{quoted_schema}.employees
        (id, company_id, employee_number, full_name, employee_type, status)
      VALUES
        (101, 73, 'EMP-101', 'Ordinary Employee', 'full_time', 'active'),
        (102, 74, 'EMP-102', 'Foreign Employee', 'full_time', 'active'),
        (103, 76, 'EMP-103', 'Other Company Employee', 'full_time', 'active'),
        (104, 73, 'EMP-104', 'Terminated Employee', 'full_time', 'terminated'),
        (105, 76, 'SYS-001', 'Protected Orchestrator', 'agent', 'active')
      """,
      []
    )
  end

  defp drop_lock_schema!(schema) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{quote_ident(schema)} CASCADE", [])
  end

  defp quote_ident(name) when is_binary(name) do
    if name =~ ~r/^[a-z0-9_]+$/ do
      name
    else
      raise "refusing to interpolate #{inspect(name)} as an identifier"
    end
  end
end
