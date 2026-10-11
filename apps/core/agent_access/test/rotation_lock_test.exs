defmodule Bilimbi.Core.AgentAccess.RotationLockTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Bilimbi.Base.Database.LockSchema
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.AgentAccess
  alias Bilimbi.Core.AgentAccess.{Connection, Device}

  setup do
    schema = create!("agent_rotation")

    tokens =
      on_schema!(schema, fn ->
        Bilimbi.Base.Tenancy.TestFixtures.create_tenants_table!(persistent: true)
        Bilimbi.Core.Company.TestFixtures.create_companies_table!(persistent: true)
        Bilimbi.Core.User.TestFixtures.create_users_table!(persistent: true)
        Bilimbi.Base.Audit.TestFixtures.create_audit_tables!(persistent: true)
        AgentAccess.TestFixtures.create_tables!(persistent: true)
        Bilimbi.Base.Tenancy.TestFixtures.insert_tenant!(%{id: 41})
        Bilimbi.Core.Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})
        Bilimbi.Core.User.TestFixtures.insert_user!(%{id: 91, company_id: 73})
        {:ok, tenant} = Tenancy.scope(41)
        scope = Authentication.sign_in(tenant, 91, 73)
        {:ok, device} = AgentAccess.start_device(AgentAccess.client_id(), "codex/model-high")

        :ok =
          AgentAccess.decide(
            scope,
            device.user_code,
            :approve,
            DateTime.add(DateTime.utc_now(), 86400)
          )

        {:ok, tokens} = AgentAccess.exchange(AgentAccess.client_id(), device.device_code)
        tokens
      end)

    %{schema: schema, tokens: tokens}
  end

  test "concurrent reuse waits for rotation, then revokes the newly issued tokens", %{
    schema: schema,
    tokens: tokens
  } do
    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            Repo.one!(from c in Connection, lock: "FOR UPDATE")
            send(parent, :held)
            await_message!(:rotate)
            AgentAccess.refresh(AgentAccess.client_id(), tokens.refresh_token)
          end)
        end)
      end)

    assert_receive :held, 5000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          send(parent, {:backend, backend_pid!()})
          AgentAccess.refresh(AgentAccess.client_id(), tokens.refresh_token)
        end)
      end)

    assert_receive {:backend, backend}, 5000
    await_row_lock!(backend)
    send(holder.pid, :rotate)
    assert {:ok, {:ok, rotated}} = Task.await(holder)
    assert {:error, :invalid_grant} = Task.await(contender)

    on_schema!(schema, fn ->
      assert {:error, :invalid_token} = AgentAccess.authenticate(rotated.access_token)

      assert {:error, :invalid_grant} =
               AgentAccess.refresh(AgentAccess.client_id(), rotated.refresh_token)
    end)
  end

  test "a device grant is redeemed once when two clients poll together", %{schema: schema} do
    device =
      on_schema!(schema, fn ->
        {:ok, tenant} = Tenancy.scope(41)
        scope = Authentication.sign_in(tenant, 91, 73)
        {:ok, device} = AgentAccess.start_device(AgentAccess.client_id(), "codex/model-high")

        :ok =
          AgentAccess.decide(
            scope,
            device.user_code,
            :approve,
            DateTime.add(DateTime.utc_now(), 86400)
          )

        device
      end)

    parent = self()

    holder =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            Repo.one!(from d in Device, where: d.status == "approved", lock: "FOR UPDATE")
            send(parent, :held)
            await_message!(:redeem)
            AgentAccess.exchange(AgentAccess.client_id(), device.device_code)
          end)
        end)
      end)

    assert_receive :held, 5000

    contender =
      Task.async(fn ->
        checkout_on_schema!(schema, fn ->
          send(parent, {:backend, backend_pid!()})
          AgentAccess.exchange(AgentAccess.client_id(), device.device_code)
        end)
      end)

    assert_receive {:backend, backend}, 5000
    await_row_lock!(backend)
    send(holder.pid, :redeem)
    assert {:ok, {:ok, _tokens}} = Task.await(holder)
    assert {:error, :invalid_grant} = Task.await(contender)
  end
end
