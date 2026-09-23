defmodule BilimbiWeb.AuditCaptureSessionTest do
  @moduledoc """
  The #630 write-session proof: real domain writes leave nonzero,
  canonically-shaped `base_audit_mutations` rows — the property whose
  absence (three opt-in callers, empty tables after a full seeded session)
  motivated ADR 0013's repo-level capture.

  The permission tests are #785's half of it. Granting and revoking a role
  or a capability reaches `RoleService`, which writes through `insert_all`
  and `delete_all`; until bulk writes were captured, the most
  audit-worthy change in the product left no row at all. These drive the
  change through the signed-in User detail screen, because the actor is
  the point: a row naming `guest` for an administrator's permission grant
  would be worse than the silence it replaced.
  """

  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    AuditFixtures.create_audit_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  defp listener_rows(auditable_type) do
    Repo.all(
      from(row in MutationSchema,
        where: row.source == "listener" and row.auditable_type == ^auditable_type,
        order_by: row.id
      )
    )
  end

  test "an Employee write session leaves shaped listener rows", %{scope: scope} do
    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-630",
        full_name: "Grace Hopper"
      })

    {:ok, _updated} =
      Employee.update_employee(scope, 73, employee.id, %{full_name: "Rear Admiral Hopper"})

    assert [created, updated] = listener_rows("Bilimbi.Core.Employee.Schema")

    assert created.event == "created"
    assert created.new_values["full_name"] == "Grace Hopper"
    assert created.auditable_id == to_string(employee.id)

    assert updated.event == "updated"
    assert updated.old_values == %{"full_name" => "Grace Hopper"}
    assert updated.new_values == %{"full_name" => "Rear Admiral Hopper"}
  end

  test "a Company write session leaves shaped listener rows with the row's tenant", %{
    scope: scope
  } do
    {:ok, _company} = Company.update_company(scope, 73, %{website: "https://example.test"})

    assert [row] = listener_rows("Bilimbi.Core.Company.Schema")
    assert row.event == "updated"
    assert row.tenant_id == 41
    assert row.new_values["website"] == "https://example.test"
  end

  test "an authenticated LiveView write records the signed-in actor", %{conn: conn} do
    grant_capabilities!(["admin.employee.list", "admin.employee.view", "admin.employee.update"])

    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{employee_number: "EMP-631", full_name: "John Doe"})

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    render_submit(view, "save_field", %{"full_name" => "John Q. Doe"})

    row =
      listener_rows("Bilimbi.Core.Employee.Schema")
      |> Enum.find(&(&1.event == "updated"))

    assert row, "the LiveView write left no listener row"
    assert row.actor_type == "user"
    assert row.actor_id == 91
    assert row.company_id == 73
    assert row.tenant_id == 41
    assert row.new_values == %{"full_name" => "John Q. Doe"}
  end

  test "without_auditing silences a session and explicit records still work", %{scope: scope} do
    Audit.without_auditing(fn ->
      {:ok, _employee} =
        Employee.create_employee(scope, 73, %{employee_number: "EMP-632", full_name: "Quiet"})
    end)

    assert listener_rows("Bilimbi.Core.Employee.Schema") == []
  end

  describe "permission changes (bulk writes)" do
    setup do
      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace Hopper",
        email: "grace@example.test"
      })

      {:ok, scope} = Tenancy.scope(41)
      {:ok, role} = Authz.create_role(scope, 73, %{name: "Auditor", code: "auditor"})

      %{role: role}
    end

    test "granting a role through the UI records the signed-in actor", %{
      conn: conn,
      role: role
    } do
      grant_capabilities!(["admin.user.view", "admin.user.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

      view |> element("#toggle-assign-roles-btn") |> render_click()

      view
      |> form("#assign-roles-form")
      |> render_submit(%{"role_ids" => ["#{role.id}"]})

      assert [granted] = listener_rows("Bilimbi.Base.Authz.PrincipalRole")
      assert granted.event == "created"
      assert granted.actor_type == "user"
      assert granted.actor_id == 91
      assert granted.company_id == 73
      assert granted.tenant_id == 41
      assert granted.new_values["principal_id"] == 92
      assert granted.new_values["role_id"] == role.id
    end

    test "revoking that role records the actor too", %{conn: conn, role: role} do
      grant_capabilities!(["admin.user.view", "admin.user.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

      view |> element("#toggle-assign-roles-btn") |> render_click()
      view |> form("#assign-roles-form") |> render_submit(%{"role_ids" => ["#{role.id}"]})

      {:ok, scope} = Tenancy.scope(41)
      [assignment] = Authz.list_principal_role_assignments(scope, :user, 92).entries

      view |> element("#remove-role-#{assignment.id}") |> render_click()
      view |> element("#user-authz-confirm-confirm") |> render_click()

      assert [_granted, revoked] = listener_rows("Bilimbi.Base.Authz.PrincipalRole")
      assert revoked.event == "deleted"
      assert revoked.actor_id == 91
      assert revoked.old_values["principal_id"] == 92
      assert revoked.old_values["role_id"] == role.id
    end

    test "granting and removing a direct capability both record the actor", %{conn: conn} do
      grant_capabilities!(["admin.user.view", "admin.user.update", "admin.company.view"])

      # The actor's own grants are themselves captured, so the assertions
      # below read what this session added, not the whole table.
      before = listener_rows("Bilimbi.Base.Authz.PrincipalCapability")

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

      view |> element("#toggle-permissions-btn") |> render_click()

      view
      |> form("#add-capabilities-form")
      |> render_submit(%{"capability_keys" => ["admin.company.view"]})

      assert [granted] = listener_rows("Bilimbi.Base.Authz.PrincipalCapability") -- before
      assert granted.event == "created"
      assert granted.actor_type == "user"
      assert granted.actor_id == 91
      assert granted.company_id == 73
      assert granted.new_values["principal_id"] == 92
      assert granted.new_values["capability_key"] == "admin.company.view"
      assert granted.new_values["is_allowed"] == true

      view |> element("#remove-direct-cap-admin-company-view") |> render_click()
      view |> element("#user-authz-confirm-confirm") |> render_click()

      assert [^granted, removed] =
               listener_rows("Bilimbi.Base.Authz.PrincipalCapability") -- before

      assert removed.event == "deleted"
      assert removed.actor_id == 91
      assert removed.old_values["capability_key"] == "admin.company.view"
    end

    test "an upsert that replaces an existing grant is an update, not a second creation" do
      {:ok, scope} = Tenancy.scope(41)
      before = listener_rows("Bilimbi.Base.Authz.PrincipalCapability")

      {:ok, :stored} =
        Authz.put_principal_capability(scope, 73, :user, 92, "admin.company.view", true)

      {:ok, :stored} =
        Authz.put_principal_capability(scope, 73, :user, 92, "admin.company.view", false)

      assert [created, replaced] =
               listener_rows("Bilimbi.Base.Authz.PrincipalCapability") -- before

      assert created.event == "created"
      assert created.new_values["is_allowed"] == true

      # The conflict-target pre-read is what makes this an update: the
      # statement's own result cannot tell a replacement from a creation.
      assert replaced.event == "updated"
      assert replaced.auditable_id == created.auditable_id
      assert replaced.old_values == %{"is_allowed" => true}
      assert replaced.new_values == %{"is_allowed" => false}
    end

    test "an excluded schema leaves no row for a bulk write" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      assert {1, nil} =
               Repo.insert_all(Bilimbi.Core.Geonames.Country, [
                 %{
                   iso: "ZZ",
                   iso3: "ZZZ",
                   iso_numeric: "999",
                   country: "Auditland",
                   continent: "EU",
                   created_at: now,
                   updated_at: now
                 }
               ])

      assert listener_rows("Bilimbi.Core.Geonames.Country") == []
    end

    test "without_auditing silences a bulk permission change", %{role: role} do
      {:ok, scope} = Tenancy.scope(41)

      Audit.without_auditing(fn ->
        {:ok, 1} = Authz.replace_role_capabilities(scope, role.id, ["admin.company.view"])
      end)

      assert listener_rows("Bilimbi.Base.Authz.RoleCapability") == []
      assert Authz.get_role(scope, role.id) |> elem(0) == :ok
    end
  end

  describe "sessions and platform provisioning" do
    test "signing out records the actor's deleted session with its payload redacted", %{
      conn: conn
    } do
      session_id = "audit-signout-session"
      conn = log_in_as(conn, %{"user_id" => 91, "company_id" => 73, "session_id" => session_id})

      {:ok, _entry} =
        Session.put_session(session_id, "_token|s:40:\"csrf-secret\";password_hash_web|x", %{
          user_id: 91,
          last_activity: System.system_time(:second)
        })

      delete(conn, ~p"/session")

      rows = listener_rows("Bilimbi.Base.Session.Schema")
      deleted = Enum.find(rows, &(&1.event == "deleted"))

      assert deleted, "signing out left no listener row"
      assert deleted.auditable_id == session_id
      assert deleted.actor_type == "user"
      assert deleted.actor_id == 91
      assert deleted.old_values["payload"] == "[redacted]"
      refute Enum.any?(rows, &(inspect({&1.old_values, &1.new_values}) =~ "csrf-secret"))
    end

    test "provisioning the platform operator records every write as guest" do
      Audit.without_auditing(fn ->
        Repo.update_all(Bilimbi.Base.Tenancy.Tenant, set: [is_platform_operator: false])
      end)

      {:ok, %{tenant: tenant, company: company, tenant_status: :created}} =
        Company.provision_platform_operator("Operator tenant", %{name: "Operator company"})

      assert [tenant_row] = listener_rows("Bilimbi.Base.Tenancy.Tenant")
      assert tenant_row.event == "created"
      assert tenant_row.auditable_id == to_string(tenant.id)

      company_row =
        listener_rows("Bilimbi.Core.Company.Schema")
        |> Enum.find(&(&1.auditable_id == to_string(company.id)))

      assert company_row, "the operator company left no listener row"

      rows = Repo.all(from(row in MutationSchema, where: row.source == "listener"))
      assert length(rows) >= 3
      assert Enum.all?(rows, &(&1.actor_type == "guest" and &1.actor_id == 0))
    end
  end
end
