defmodule Bilimbi.Core.User.AdminBootstrapLockTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Database.LockSchema
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures

  test "an account being inserted concurrently makes bootstrap refuse after waiting" do
    schema = LockSchema.create!("user_bootstrap_lock")

    LockSchema.on_schema!(schema, fn ->
      TestFixtures.create_users_table!(persistent: true)
      TestFixtures.create_bootstrap_receipt_table!(persistent: true)
    end)

    parent = self()
    supervisor = start_supervised!(Task.Supervisor)

    holder =
      Task.Supervisor.async_nolink(supervisor, fn ->
        LockSchema.checkout_on_schema!(schema, fn ->
          Repo.transact(fn ->
            TestFixtures.insert_user!(%{company_id: nil})
            send(parent, :account_inserted)
            LockSchema.await_message!(:commit)
            {:ok, :ok}
          end)
        end)
      end)

    assert_receive :account_inserted, 5_000

    contender =
      Task.Supervisor.async_nolink(supervisor, fn ->
        LockSchema.checkout_on_schema!(schema, fn ->
          send(parent, {:contender_backend, LockSchema.backend_pid!()})

          User.bootstrap_platform_admin(%{
            tenant_name: "Operator",
            company_name: "Operations",
            company_code: "operations",
            admin_name: "Admin",
            admin_email: "admin@example.com",
            password: "bootstrap-password"
          })
        end)
      end)

    assert_receive {:contender_backend, backend}, 5_000
    LockSchema.await_row_lock!(backend)
    send(holder.pid, :commit)
    assert {:ok, :ok} = Task.await(holder)
    assert {:error, :existing_users} = Task.await(contender)
  end
end
