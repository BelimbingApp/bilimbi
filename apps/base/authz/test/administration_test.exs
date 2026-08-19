defmodule Bilimbi.Base.Authz.AdministrationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.Page
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalCapabilitySummary
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleDetails
  alias Bilimbi.Base.Authz.RoleSummary
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope

  import Bilimbi.Base.Authz.TestFixtures

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "role administration stays scoped and protects system roles" do
    tenant_scope = scope()

    assert {:ok, role} =
             Authz.create_role(tenant_scope, 10, %{
               name: "Local viewer",
               code: "local_viewer",
               description: "Initial"
             })

    assert {:ok, 1} =
             Authz.replace_role_capabilities(tenant_scope, role.id, ["admin.test.record.view"])

    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 10, :user, 7, role.id)

    assert {:ok,
            %RoleDetails{
              role: %RoleSummary{capability_count: 1, principal_count: 1},
              capabilities: ["admin.test.record.view"],
              principal_roles: [assignment]
            }} = Authz.get_role(tenant_scope, role.id)

    assert assignment.company_id == 10
    assert assignment.principal_type == "user"
    assert assignment.principal_id == 7

    assert {:error, :role_has_principals} =
             Authz.update_role(tenant_scope, role.id, %{company_id: 11})

    assert {:error, :role_not_found} = Authz.unassign_role(scope(2), role.id, assignment.id)
    assert {:ok, :unassigned} = Authz.unassign_role(tenant_scope, role.id, assignment.id)
    assert {:ok, :not_found} = Authz.unassign_role(tenant_scope, role.id, assignment.id)

    assert {:ok, %RoleSummary{company_id: 11, name: "Renamed"}} =
             Authz.update_role(tenant_scope, role.id, %{
               "company_id" => "11",
               "name" => "Renamed"
             })

    assert {:error, :not_found} = Authz.get_role(scope(2), role.id)

    assert %Page{
             entries: [%RoleSummary{id: listed_id, capability_count: 1, principal_count: 0}],
             total_entries: 1,
             total_pages: 1
           } = Authz.list_roles(tenant_scope, search: "renam", page_size: 1)

    assert listed_id == role.id

    assert {:ok, _result} = Authz.reconcile_system_roles()
    system_role = Repo.one!(from(item in Role, where: item.is_system, limit: 1))

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(PrincipalRole, [
      %{
        company_id: 99,
        principal_type: "user",
        principal_id: 99,
        role_id: system_role.id,
        created_at: now,
        updated_at: now
      }
    ])

    assert %Page{entries: [%RoleSummary{principal_count: 0}]} =
             Authz.list_roles(tenant_scope, search: system_role.code)

    assert {:error, :system_role} =
             Authz.update_role(tenant_scope, system_role.id, %{name: "Forbidden"})

    assert {:error, :system_role} = Authz.delete_role(tenant_scope, system_role.id)
    assert {:ok, :deleted} = Authz.delete_role(tenant_scope, role.id)
    assert {:error, :not_found} = Authz.get_role(tenant_scope, role.id)
  end

  test "direct capability pages distinguish an explicit deny from removal" do
    tenant_scope = scope()
    actor = Authz.actor(:user, 7, tenant_scope, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "admin.test.record.view",
               false
             )

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               11,
               :agent,
               8,
               "admin.test.record.view",
               true
             )

    assert %Page{
             entries: [
               denied_grant = %PrincipalCapabilitySummary{allowed: false, principal_type: "user"}
             ],
             total_entries: 1,
             total_pages: 1
           } =
             Authz.list_principal_capabilities(tenant_scope,
               allowed: false,
               page_size: 1,
               sort_by: :principal_id,
               sort_dir: :asc
             )

    assert Authz.can(actor, "admin.test.record.view").reason == :denied_explicitly

    assert {:ok, :removed} =
             Authz.remove_principal_capability(tenant_scope, denied_grant.id)

    assert {:ok, :not_found} =
             Authz.remove_principal_capability(tenant_scope, denied_grant.id)

    refute Authz.can(actor, "admin.test.record.view").allowed
    refute Authz.can(actor, "admin.test.record.view").reason == :denied_explicitly

    assert %Page{total_entries: 0, entries: []} =
             Authz.list_principal_capabilities(scope(2))

    assert %Page{entries: [other_grant]} =
             Authz.list_principal_capabilities(tenant_scope, allowed: true)

    assert {:ok, :not_found} =
             Authz.remove_principal_capability(scope(2), other_grant.id)

    stale_grant =
      Repo.insert!(%PrincipalCapability{
        company_id: 10,
        principal_type: "user",
        principal_id: 9,
        capability_key: "retired.capability",
        is_allowed: true
      })

    assert {:ok, :removed} = Authz.remove_principal_capability(tenant_scope, stale_grant.id)
  end

  test "principal read models are bounded, ordered, and scoped without resolving principal ownership" do
    tenant_scope = scope()

    assert {:ok, custom_role} =
             Authz.create_role(tenant_scope, 10, %{
               name: "Custom role",
               code: "custom_role",
               description: "Tenant role"
             })

    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 10, :user, 7, custom_role.id)
    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 11, :agent, 7, custom_role.id)
    assert {:ok, _result} = Authz.reconcile_system_roles()
    system_role = Repo.one!(from(item in Role, where: item.is_system, limit: 1))
    assert {:ok, :assigned} = Authz.assign_role(tenant_scope, 10, :user, 7, system_role.id)
    system_role_id = system_role.id
    custom_role_id = custom_role.id

    assert %Page{entries: assignments, total_entries: 2, total_pages: 1} =
             Authz.list_principal_role_assignments(tenant_scope, :user, 7, page_size: 2)

    assert Enum.map(assignments, & &1.role_code) ==
             Enum.sort(Enum.map(assignments, & &1.role_code))

    assert %{
             company_id: 10,
             principal_type: "user",
             principal_id: 7,
             role_id: ^system_role_id,
             role_is_system: true
           } = Enum.find(assignments, &(&1.role_id == system_role_id))

    assert %{
             id: custom_assignment_id,
             role_id: ^custom_role_id,
             role_name: "Custom role",
             role_code: "custom_role",
             role_is_system: false,
             role_grant_all: false
           } = Enum.find(assignments, &(&1.role_id == custom_role_id))

    assert %Page{entries: [%{principal_type: "agent", principal_id: 7}], total_entries: 1} =
             Authz.list_principal_role_assignments(tenant_scope, :agent, 7)

    assert %Page{entries: [], total_entries: 0} =
             Authz.list_principal_role_assignments(scope(2), :user, 7)

    # Base Authz receives only the opaque principal identity. With no persisted
    # company-scoped rows, it cannot invent tenant context for this user ID.
    assert %Page{entries: [], total_entries: 0} =
             Authz.list_principal_role_assignments(tenant_scope, :user, 88)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "admin.test.record.view",
               true
             )

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               11,
               :agent,
               7,
               "admin.test.record.view",
               false
             )

    assert %Page{
             entries: [
               %PrincipalCapabilitySummary{
                 principal_type: "user",
                 principal_id: 7,
                 allowed: true
               }
             ],
             total_entries: 1
           } =
             Authz.list_principal_capabilities(tenant_scope,
               principal_type: :user,
               principal_id: 7
             )

    assert %Page{entries: [], total_entries: 0} =
             Authz.list_principal_capabilities(scope(2), principal_type: :user, principal_id: 7)

    assert {:ok, :unassigned} =
             Authz.unassign_role(tenant_scope, custom_role.id, custom_assignment_id)

    assert {:ok, :not_found} =
             Authz.unassign_role(tenant_scope, custom_role.id, custom_assignment_id)
  end

  test "only platform operators can inspect and remove effective global rows" do
    tenant_scope = scope()
    platform_scope = platform_operator_scope()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    assert {:ok, _result} = Authz.reconcile_system_roles()
    system_role = Repo.one!(from(item in Role, where: item.is_system, limit: 1))

    global_deny =
      Repo.insert!(%PrincipalCapability{
        company_id: nil,
        principal_type: "user",
        principal_id: 70,
        capability_key: "admin.test.record.view",
        is_allowed: false,
        created_at: now,
        updated_at: now
      })

    global_allow =
      Repo.insert!(%PrincipalCapability{
        company_id: nil,
        principal_type: "user",
        principal_id: 71,
        capability_key: "admin.test.record.view",
        is_allowed: true,
        created_at: now,
        updated_at: now
      })

    global_assignment =
      Repo.insert!(%PrincipalRole{
        company_id: nil,
        principal_type: "user",
        principal_id: 72,
        role_id: system_role.id,
        created_at: now,
        updated_at: now
      })

    assert Authz.can(Authz.actor(:user, 70, tenant_scope, 10), "admin.test.record.view").reason ==
             :denied_explicitly

    assert Authz.can(Authz.actor(:user, 71, tenant_scope, 10), "admin.test.record.view").allowed
    assert Authz.can(Authz.actor(:user, 72, tenant_scope, 10), "admin.test.record.view").allowed

    assert %Page{entries: [], total_entries: 0} =
             Authz.list_principal_capabilities(tenant_scope)

    assert %Page{entries: [], total_entries: 0} =
             Authz.list_principal_capabilities(tenant_scope,
               principal_type: :user,
               principal_id: 70
             )

    assert %Page{entries: operator_grants, total_entries: 2} =
             Authz.list_principal_capabilities(platform_scope)

    assert Enum.sort(Enum.map(operator_grants, & &1.id)) ==
             Enum.sort([global_deny.id, global_allow.id])

    assert %Page{entries: [%{id: global_deny_id, allowed: false}], total_entries: 1} =
             Authz.list_principal_capabilities(platform_scope,
               principal_type: :user,
               principal_id: 70
             )

    assert global_deny_id == global_deny.id

    assert {:ok, %RoleDetails{role: %RoleSummary{principal_count: 0}, principal_roles: []}} =
             Authz.get_role(tenant_scope, system_role.id)

    assert {:ok,
            %RoleDetails{
              role: %RoleSummary{principal_count: 1},
              principal_roles: [visible_assignment]
            }} = Authz.get_role(platform_scope, system_role.id)

    assert %Page{entries: [%RoleSummary{principal_count: 0}]} =
             Authz.list_roles(tenant_scope, search: system_role.code)

    assert %Page{entries: [%RoleSummary{principal_count: 1}]} =
             Authz.list_roles(platform_scope, search: system_role.code)

    assert visible_assignment.id == global_assignment.id
    assert {:ok, :not_found} = Authz.remove_principal_capability(tenant_scope, global_deny.id)

    assert {:ok, :not_found} =
             Authz.unassign_role(tenant_scope, system_role.id, global_assignment.id)

    assert {:ok, :removed} =
             Authz.remove_principal_capability(platform_scope, global_deny.id)

    assert {:ok, :removed} =
             Authz.remove_principal_capability(platform_scope, global_allow.id)

    assert {:ok, :unassigned} =
             Authz.unassign_role(platform_scope, system_role.id, global_assignment.id)

    refute Authz.can(Authz.actor(:user, 70, tenant_scope, 10), "admin.test.record.view").allowed
    refute Authz.can(Authz.actor(:user, 71, tenant_scope, 10), "admin.test.record.view").allowed
    refute Authz.can(Authz.actor(:user, 72, tenant_scope, 10), "admin.test.record.view").allowed
  end

  test "decision-log pages are tenant-scoped, filterable, and payload-safe" do
    tenant_scope = scope()
    actor = Authz.actor(:user, 7, tenant_scope, 10)

    refute Authz.can(
             actor,
             "admin.test.record.view",
             Authz.resource("record", "alpha"),
             %{trace_id: "firsttrace1234"}
           ).allowed

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "admin.test.record.view",
               true
             )

    assert Authz.can(
             actor,
             "admin.test.record.view",
             Authz.resource("record", "beta"),
             %{trace_id: "secondtrace123"}
           ).allowed

    Repo.insert!(
      DecisionLog.changeset(%{
        company_id: 99,
        actor_type: "user",
        actor_id: 99,
        capability: "admin.test.record.view",
        allowed: true,
        reason_code: "allowed_directly",
        occurred_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
    )

    assert %Page{total_entries: 2, total_pages: 1} =
             Authz.list_decision_logs(tenant_scope)

    assert %Page{entries: [entry], total_entries: 1} =
             Authz.list_decision_logs(tenant_scope,
               allowed: false,
               search: "record",
               page_size: 1
             )

    assert entry.actor_type == "user"
    assert entry.reason == "denied_missing_capability"
    assert entry.resource_id == "alpha"
    refute Map.has_key?(Map.from_struct(entry), :context)
    refute Map.has_key?(Map.from_struct(entry), :applied_policies)

    assert %Page{entries: [], total_entries: 0} = Authz.list_decision_logs(scope(2))
  end

  test "principal capabilities sort by supplied company_order across pages" do
    tenant_scope = scope()

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               1,
               "admin.test.record.view",
               true
             )

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               11,
               :user,
               2,
               "admin.test.record.view",
               true
             )

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               tenant_scope,
               10,
               :user,
               3,
               "admin.test.record.view",
               true
             )

    # Numeric ids are 10 then 11; name order is handed in as 11 then 10.
    page_one =
      Authz.list_principal_capabilities(tenant_scope,
        sort_by: :company_name,
        sort_dir: :asc,
        page: 1,
        page_size: 1,
        company_order: [11, 10]
      )

    page_two =
      Authz.list_principal_capabilities(tenant_scope,
        sort_by: :company_name,
        sort_dir: :asc,
        page: 2,
        page_size: 1,
        company_order: [11, 10]
      )

    assert page_one.total_entries == 3
    assert [%PrincipalCapabilitySummary{company_id: 11}] = page_one.entries
    assert [%PrincipalCapabilitySummary{company_id: 10, principal_id: 1}] = page_two.entries
  end

  test "administration options reject unbounded or unknown input" do
    assert_raise ArgumentError, ~r/page_size/, fn ->
      Authz.list_decision_logs(scope(), page_size: 101)
    end

    assert_raise ArgumentError, ~r/sort_by/, fn ->
      Authz.list_principal_capabilities(scope(), sort_by: :private_schema_field)
    end

    assert_raise ArgumentError, ~r/unknown keys/, fn ->
      Authz.list_roles(scope(), unsafe_query: true)
    end

    assert_raise ArgumentError, ~r/principal filter/, fn ->
      Authz.list_principal_capabilities(scope(), principal_type: :user)
    end

    assert_raise ArgumentError, ~r/principal filter/, fn ->
      Authz.list_principal_role_assignments(scope(), :service, 7)
    end
  end

  defp platform_operator_scope do
    Scope.for_tenant(%Identity{
      id: 1,
      name: "Platform",
      status: "active",
      is_platform_operator: true
    })
  end
end
