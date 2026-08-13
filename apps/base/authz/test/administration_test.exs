defmodule Bilimbi.Base.Authz.AdministrationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.Page
  alias Bilimbi.Base.Authz.PrincipalCapabilitySummary
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleDetails
  alias Bilimbi.Base.Authz.RoleSummary
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo

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
             entries: [%PrincipalCapabilitySummary{allowed: false, principal_type: "user"}],
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
             Authz.remove_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "ADMIN.TEST.RECORD.VIEW"
             )

    assert {:ok, :not_found} =
             Authz.remove_principal_capability(
               tenant_scope,
               10,
               :user,
               7,
               "admin.test.record.view"
             )

    refute Authz.can(actor, "admin.test.record.view").allowed
    refute Authz.can(actor, "admin.test.record.view").reason == :denied_explicitly

    assert %Page{total_entries: 0, entries: []} =
             Authz.list_principal_capabilities(scope(2))

    assert {:error, :company_not_found} =
             Authz.remove_principal_capability(
               tenant_scope,
               99,
               :user,
               7,
               "admin.test.record.view"
             )
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
  end
end
