defmodule Bilimbi.Core.Company.ExternalAccessLockTest do
  @moduledoc false

  # async: false — two real connections must observe each other's uncommitted
  # row locks. Temp-table DataCase tests cannot do that.
  use ExUnit.Case, async: false

  import Bilimbi.Base.Database.LockSchema

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Ecto.Adapters.SQL

  test "a waiting delete returns not_found after the lock holder commits a soft-delete" do
    schema = create!("company_ext_access_lock")

    {scope, access_id} =
      on_schema!(schema, fn ->
        seed!()
        {:ok, scope} = Tenancy.scope(41)

        {:ok, access} =
          Company.create_external_access(scope, 73, %{relationship_id: 21})

        {scope, access.id}
      end)

    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            %{rows: [[^access_id]]} =
              SQL.query!(
                Repo,
                "SELECT id FROM company_external_accesses WHERE id = $1 FOR UPDATE",
                [access_id]
              )

            send(parent, :holder_locked)

            receive do
              :commit_delete -> :ok
            after
              5_000 -> Repo.rollback(:holder_timeout)
            end

            Company.delete_external_access(scope, 73, access_id)
          end)
        end)
      end)

    assert_receive :holder_locked, 5_000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          send(parent, {:contender_backend, backend_pid!()})
          Company.delete_external_access(scope, 73, access_id)
        end)
      end)

    assert_receive {:contender_backend, backend_pid}, 5_000
    await_row_lock!(backend_pid)
    send(holder.pid, :commit_delete)

    assert {:ok, :ok} = Task.await(holder, 5_000)
    assert {:error, :not_found} = Task.await(contender, 5_000)

    on_schema!(schema, fn ->
      assert {:error, :not_found} = Company.get_external_access(scope, 73, access_id)
    end)
  end

  # update/revoke/delete share mutate_live_access/4 (FOR UPDATE, then mutate).
  # One delete-vs-delete wait/recheck proves the helper: the waiter re-evaluates
  # `deleted_at IS NULL` after the holder commits.

  defp seed! do
    TenancyFixtures.create_tenants_table!(persistent: true)
    CompanyFixtures.create_companies_table!(persistent: true)
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!(persistent: true)
    CompanyFixtures.create_external_access_tables!(persistent: true)
    TenancyFixtures.insert_tenant!(%{id: 41, name: "Platform operator"})
    CompanyFixtures.insert_company!()
    CompanyFixtures.insert_relationship_type!(11)
    CompanyFixtures.insert_relationship!(21, 73, 73, 11)
  end
end
