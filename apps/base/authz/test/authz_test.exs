defmodule Bilimbi.Base.AuthzTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleCapability
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo

  import Bilimbi.Base.Authz.TestFixtures

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "actor construction requires explicit valid tenant and company context" do
    tenant_scope = scope()

    assert %Authz.Actor{type: :user, id: 7, company_id: 10} =
             Authz.actor(:user, 7, tenant_scope, 10)

    assert_raise ArgumentError, ~r/acting_for_user_id/, fn ->
      Authz.actor(:agent, 8, tenant_scope, 10)
    end

    assert %Authz.Actor{type: :agent, acting_for_user_id: 7} =
             Authz.actor(:agent, 8, tenant_scope, 10, acting_for_user_id: 7)
  end

  test "unknown capabilities fail closed before stale persisted grants" do
    actor = Authz.actor(:user, 7, scope(), 10)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(PrincipalCapability, [
      %{
        company_id: 10,
        principal_type: "user",
        principal_id: 7,
        capability_key: "admin.removed.record.view",
        is_allowed: true,
        created_at: now,
        updated_at: now
      }
    ])

    decision = Authz.can(actor, "admin.removed.record.view", nil, %{trace_id: "abcdefghijklmnop"})

    refute decision.allowed
    assert decision.reason == :denied_unknown_capability

    assert %DecisionLog{trace_id: "abcdefghijkl", reason_code: "denied_unknown_capability"} =
             Repo.one!(DecisionLog)

    assert %{
             role_grants: [],
             principal_grants: [%{capability: "admin.removed.record.view", allowed: true}]
           } = Authz.unknown_persisted_capabilities()
  end

  test "direct deny overrides role grants and grant-all" do
    tenant_scope = scope()
    actor = Authz.actor(:user, 7, tenant_scope, 10)

    assert {:ok, _summary} = Authz.reconcile_system_roles()

    all_access = system_role("all_access")
    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 10, :user, 7, all_access.id)

    assert Authz.can(actor, "admin.test.record.view").allowed

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "admin.test.record.view",
               false
             )

    decision = Authz.can(actor, "admin.test.record.view")
    refute decision.allowed
    assert decision.reason == :denied_explicitly
  end

  test "custom roles are tenant-scoped and grant their known capabilities" do
    tenant_scope = scope()
    actor = Authz.actor(:user, 9, tenant_scope, 10)

    assert {:error, :company_not_found} =
             Authz.create_role(tenant_scope, 99, %{name: "Wrong tenant", code: "wrong"})

    assert {:ok, role} =
             Authz.create_role(tenant_scope, 10, %{name: "Local viewer", code: "local_viewer"})

    assert {:ok, 1} =
             Authz.replace_role_capabilities(
               tenant_scope,
               role.id,
               ["admin.test.record.view"]
             )

    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 10, :user, 9, role.id)
    assert {:ok, :existing} = Authz.assign_role(tenant_scope, 10, :user, 9, role.id)
    assert Authz.can(actor, "admin.test.record.view").allowed
  end

  test "resource tenant and company policies reject cross-boundary access" do
    actor = Authz.actor(:user, 7, scope(), 10)
    assert {:ok, _summary} = Authz.reconcile_system_roles()
    all_access = system_role("all_access")
    assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, 7, all_access.id)

    tenant_decision =
      Authz.can(actor, "admin.test.record.view", Authz.resource("record", 1, scope: scope(2)))

    company_decision =
      Authz.can(actor, "admin.test.record.view", Authz.resource("record", 1, company_id: 11))

    assert tenant_decision.reason == :denied_tenant_scope
    assert company_decision.reason == :denied_company_scope
  end

  test "system-role reconciliation is idempotent and preserves principal grants" do
    tenant_scope = scope()

    assert {:ok, %{roles: 2, capabilities: 1}} = Authz.reconcile_system_roles()
    viewer = system_role("viewer")
    assert Repo.aggregate(RoleCapability, :count) == 1

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(RoleCapability, [
      %{
        role_id: viewer.id,
        capability_key: "admin.removed.record.view",
        created_at: now,
        updated_at: now
      }
    ])

    assert [%{capability: "admin.removed.record.view"}] =
             Authz.unknown_persisted_capabilities().role_grants

    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 10, :user, 7, viewer.id)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "admin.test.record.view",
               true
             )

    assert {:ok, %{roles: 2, capabilities: 1}} = Authz.reconcile_system_roles()
    assert Repo.aggregate(Role, :count) == 2
    assert Repo.aggregate(RoleCapability, :count) == 1
    assert Repo.aggregate(PrincipalRole, :count) == 1
    assert Repo.aggregate(PrincipalCapability, :count) == 1
  end

  defp system_role(code) do
    Repo.one!(from(role in Role, where: role.code == ^code and is_nil(role.company_id)))
  end
end
