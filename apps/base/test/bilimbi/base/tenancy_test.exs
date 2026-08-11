defmodule Bilimbi.Base.TenancyTest do
  use Bilimbi.Base.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError

  import Bilimbi.Base.TenancyFixtures

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

  test "reports an unprovisioned operator without assigning meaning to an ID" do
    insert_tenant!(%{id: 1, is_platform_operator: false})

    assert Tenancy.platform_operator() == nil
    assert_raise NotProvisionedError, &Tenancy.require_platform_operator!/0
  end

  test "rejects a soft-deleted marked operator" do
    insert_tenant!(%{deleted_at: ~N[2026-08-11 12:00:00]})

    assert_raise InvariantError, &Tenancy.platform_operator/0
  end
end
