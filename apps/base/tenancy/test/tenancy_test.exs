defmodule Bilimbi.Base.TenancyTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError
  alias Bilimbi.Base.Tenancy.SchemaContract

  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    :ok
  end

  test "resolves the explicitly marked live platform operator" do
    insert_tenant!(%{id: 41})

    tenant = Tenancy.platform_operator()

    assert tenant.id == 41
    assert Tenancy.platform_operator?(tenant)
    assert Tenancy.require_platform_operator!().id == 41
  end

  test "exposes tenant identity without leaking the Ecto schema and owns locked reads" do
    insert_tenant!(%{id: 41, is_platform_operator: false})

    assert {:ok, tenant} = Tenancy.lock_tenant(41)
    assert tenant.id == 41
    refute Map.has_key?(tenant, :__meta__)
    assert {:error, :not_found} = Tenancy.fetch_tenant(999)
  end

  test "reports an unprovisioned operator without assigning meaning to an ID" do
    insert_tenant!(%{id: 1, is_platform_operator: false})

    assert Tenancy.platform_operator() == nil
    assert_raise NotProvisionedError, &Tenancy.require_platform_operator!/0
  end

  test "rejects a soft-deleted marked operator" do
    insert_tenant!(%{deleted_at: ~N[2026-08-11 12:00:00]})

    assert {:error, [error]} =
             SchemaContract.verify_invariants(Repo, prefix: temporary_schema!())

    assert error =~ "platform-operator tenant 41 is soft-deleted"
    assert_raise InvariantError, &Tenancy.platform_operator/0
  end

  test "provisions one generated operator and updates it idempotently" do
    assert {:ok, first, :created} = Tenancy.provision_platform_operator("Initial operator")
    assert first.is_platform_operator

    assert {:ok, second, :existing} = Tenancy.provision_platform_operator("Renamed operator")
    assert second.id == first.id
    assert second.name == "Renamed operator"
    assert Tenancy.platform_operator().id == first.id
  end

  test "normal tenant creation cannot smuggle operator identity or an ID" do
    assert {:ok, tenant} =
             Tenancy.create_tenant(%{
               id: 999,
               name: "Customer tenant",
               is_platform_operator: true
             })

    assert tenant.id != 999
    refute tenant.is_platform_operator
  end
end
