defmodule Bilimbi.Core.Company.LiveLockTest do
  @moduledoc false

  # async: false — this contract requires two independently checked-out
  # PostgreSQL connections that can observe each other's row locks.
  use ExUnit.Case, async: false

  import Bilimbi.Base.Database.LockSchema

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.LiveCompanyProof
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Ecto.Adapters.SQL

  setup do
    schema = create!("company_live_lock")

    on_schema!(schema, fn ->
      TenancyFixtures.create_tenants_table!(persistent: true)
      CompanyFixtures.create_companies_table!(persistent: true)
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
    end)

    scope = on_schema!(schema, fn -> elem(Tenancy.scope(41), 1) end)

    %{schema: schema, scope: scope}
  end

  test "requires an explicit shared Repo transaction", %{schema: schema, scope: scope} do
    on_schema!(schema, fn ->
      refute Repo.in_transaction?()
      assert {:error, :transaction_required} = Company.lock_live_company(scope, 73)

      assert {:ok, {:ok, %LiveCompanyProof{id: 73}}} =
               Repo.transaction(fn ->
                 assert Repo.in_transaction?()
                 Company.lock_live_company(scope, 73)
               end)
    end)
  end

  test "returns generic misses and keeps its proof schema-free", %{schema: schema, scope: scope} do
    on_schema!(schema, fn ->
      assert {:ok, {:ok, %LiveCompanyProof{id: 73} = proof}} =
               Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)

      assert Map.keys(Map.from_struct(proof)) == [:id]
      refute is_struct(proof, Schema)
      refute Map.has_key?(proof, :__meta__)

      assert Ecto.Queryable.impl_for(proof) == nil

      for company_id <- [0, -1, nil, "73", 74, 75] do
        assert {:ok, {:error, :not_found}} =
                 Repo.transaction(fn -> Company.lock_live_company(scope, company_id) end)
      end
    end)
  end

  test "rejects a malformed scope at the public boundary", %{schema: schema} do
    on_schema!(schema, fn ->
      assert_raise FunctionClauseError, fn ->
        Repo.transaction(fn -> apply(Company, :lock_live_company, [41, 73]) end)
      end
    end)
  end

  test "rollback releases a proof lock without returning a durable capability", %{
    schema: schema,
    scope: scope
  } do
    on_schema!(schema, fn ->
      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 assert {:ok, %LiveCompanyProof{id: 73}} = Company.lock_live_company(scope, 73)
                 Repo.rollback(:rollback)
               end)

      assert {:ok, {:ok, %LiveCompanyProof{id: 73}}} =
               Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)
    end)
  end

  test "the proof retains its row lock until commit", %{schema: schema, scope: scope} do
    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            assert {:ok, %LiveCompanyProof{id: 73}} = Company.lock_live_company(scope, 73)
            send(parent, :holder_locked)
            await_message!(:commit_holder)
          end)
        end)
      end)

    assert_receive :holder_locked, 5_000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          send(parent, {:contender_backend, backend_pid!()})

          SQL.query!(
            Repo,
            "UPDATE companies SET deleted_at = '2026-08-14 00:00:00' WHERE id = $1",
            [73]
          )
        end)
      end)

    assert_receive {:contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :commit_holder)

    assert {:ok, :ok} = Task.await(holder, 5_000)
    assert %{num_rows: 1} = Task.await(contender, 5_000)

    on_schema!(schema, fn ->
      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)
    end)
  end

  test "a waiting proof rechecks after a competing soft-delete commits", %{
    schema: schema,
    scope: scope
  } do
    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            %{rows: [[73]]} =
              SQL.query!(Repo, "SELECT id FROM companies WHERE id = 73 FOR UPDATE", [])

            send(parent, :delete_holder_locked)
            await_message!(:soft_delete_and_commit)

            SQL.query!(
              Repo,
              "UPDATE companies SET deleted_at = '2026-08-14 00:00:00' WHERE id = $1",
              [73]
            )
          end)
        end)
      end)

    assert_receive :delete_holder_locked, 5_000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          send(parent, {:proof_contender_backend, backend_pid!()})

          Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)
        end)
      end)

    assert_receive {:proof_contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :soft_delete_and_commit)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end
end
