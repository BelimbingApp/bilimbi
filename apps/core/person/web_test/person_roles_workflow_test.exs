defmodule BilimbiWeb.PersonRolesWorkflowTest do
  use BilimbiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{AgentApi, Authz, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Person
  alias Bilimbi.Core.Company.TestFixtures, as: Companies

  @caps ~w(admin.person.list admin.person.view admin.person.create admin.person.update admin.company.view admin.company.list admin.company.tenant-wide.manage)

  setup do
    signed_in_identity!()
    Person.TestFixtures.create_person_tables!()
    AgentApi.TestFixtures.create_plan_tables!()
    Companies.create_external_access_tables!()
    :ok = Company.RelationshipCatalogue.ensure_defaults(Bilimbi.Base.Repo)
    Companies.insert_company!(%{id: 74, code: "vendor", name: "Vendor Ltd"})
    Companies.insert_tenant!(%{id: 42, is_platform_operator: false})
    Companies.insert_company!(%{id: 75, tenant_id: 42, code: "foreign", name: "Foreign Ltd"})
    {:ok, system} = Tenancy.scope(41)
    scope = Authentication.sign_in(system, 91, 73)
    {:ok, roles} = Company.list_relationship_types()
    {:ok, lead} = Person.create(system, %{full_name: "Lena Lead"})
    %{scope: scope, system: system, lead: lead, roles: Map.new(roles, &{&1.code, &1})}
  end

  test "UI assigns and unlinks a prospect role for a bare person without access grants", %{
    conn: conn,
    scope: scope,
    lead: lead,
    roles: roles
  } do
    grant_capabilities!(@caps)
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts/#{lead.id}")
    assert has_element?(view, "#role-type option[value='#{roles["prospect"].id}']")
    refute has_element?(view, "#role-company option[value='75']")

    view
    |> form("#role-form",
      role: %{company_id: "73", relationship_type_id: "#{roles["prospect"].id}"}
    )
    |> render_submit()

    assert {:ok, [%{role_code: "prospect", id: id}]} = Person.relationships(scope, lead.id)
    assert has_element?(view, "#contact-roles", "Prospect")

    view |> element("#unlink-role-#{id}") |> render_click()
    assert {:ok, []} = Person.relationships(scope, lead.id)

    assert {:ok, [%{unlinked_at: %NaiveDateTime{}}]} =
             Person.relationships(scope, lead.id, include_unlinked: true)

    assert {:ok, []} = Bilimbi.Core.Employee.list_employees(scope, 73)
    assert {:ok, [%{id: 91}]} = Bilimbi.Core.User.list_users(scope)
  end

  test "UI ends a prospect role with a date, keeps it as history, then starts the customer role",
       %{conn: conn, scope: scope, lead: lead, roles: roles} do
    grant_capabilities!(@caps)
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts/#{lead.id}")

    view
    |> form("#role-form",
      role: %{
        company_id: "73",
        relationship_type_id: "#{roles["prospect"].id}",
        effective_from: "2026-01-01"
      }
    )
    |> render_submit()

    assert {:ok, [%{id: id}]} = Person.relationships(scope, lead.id)
    view |> element("#end-role-#{id}") |> render_click()
    assert has_element?(view, "#role-dates-modal")
    refute has_element?(view, "#role-dates-from")
    today = Date.to_iso8601(Date.utc_today())
    assert has_element?(view, "#role-dates-to[value='#{today}']")

    view
    |> form("#role-dates-form", role_dates: %{effective_to: "2026-03-31"})
    |> render_submit()

    refute has_element?(view, "#role-dates-modal")
    assert has_element?(view, "#flash-success", "Role ended")
    assert has_element?(view, "#contact-roles", "2026-03-31")

    view
    |> form("#role-form",
      role: %{
        company_id: "73",
        relationship_type_id: "#{roles["customer"].id}",
        effective_from: "2026-04-01"
      }
    )
    |> render_submit()

    assert {:ok, rows} = Person.relationships(scope, lead.id)

    assert [{"prospect", ~D[2026-01-01], ~D[2026-03-31]}, {"customer", ~D[2026-04-01], nil}] ==
             Enum.map(rows, &{&1.role_code, &1.effective_from, &1.effective_to})

    view |> element("#edit-role-#{id}") |> render_click()
    assert has_element?(view, "#role-dates-from[value='2026-01-01']")

    view
    |> form("#role-dates-form",
      role_dates: %{effective_from: "2025-12-01", effective_to: "2026-03-30"}
    )
    |> render_submit()

    assert {:ok, [%{effective_from: ~D[2025-12-01], effective_to: ~D[2026-03-30]} | _]} =
             Person.relationships(scope, lead.id)

    view |> element("#unlink-role-#{id}") |> render_click()
    assert has_element?(view, "#role-unlinked-#{id}")
    refute has_element?(view, "#end-role-#{id}")
  end

  test "agents end a person role by date and keep it as history", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    grant_capabilities!(@caps)

    {:ok, rel} =
      Person.create_relationship(scope, lead.id, 73, %{
        relationship_type_id: roles["prospect"].id,
        effective_from: "2026-01-01"
      })

    op = %{
      "key" => "core.person.relationship.end",
      "input" => %{
        "person_id" => lead.id,
        "relationship_id" => rel.id,
        "effective_to" => "2026-03-31"
      }
    }

    assert {:ok, plan} = AgentApi.plan(scope, [op])
    assert plan["valid"]
    assert {:ok, [%{effective_to: nil}]} = Person.relationships(scope, lead.id)
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [op])

    assert {:ok, [%{effective_to: ~D[2026-03-31], unlinked_at: nil}]} =
             Person.relationships(scope, lead.id)

    foreign = put_in(op, ["input", "person_id"], 999_999)
    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [foreign])
  end

  test "forged UI company and missing write capability cannot assign a role", %{
    conn: conn,
    scope: scope,
    lead: lead,
    roles: roles
  } do
    grant_capabilities!(@caps)
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts/#{lead.id}")
    type = "#{roles["customer"].id}"

    render_submit(view, "add_role", %{
      "role" => %{"company_id" => "75", "relationship_type_id" => type}
    })

    assert {:ok, []} = Person.relationships(scope, lead.id)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, 73, :user, 91, "admin.person.update", false)

    render_submit(view, "add_role", %{
      "role" => %{"company_id" => "73", "relationship_type_id" => type}
    })

    assert {:ok, []} = Person.relationships(scope, lead.id)
  end

  test "agents discover, plan and commit person roles; foreign targets are denied", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    grant_capabilities!(@caps)
    assert {:ok, description} = AgentApi.describe(scope, "core.person.relationship.create")
    assert description

    create = fn company_id ->
      %{
        "key" => "core.person.relationship.create",
        "input" => %{
          "person_id" => lead.id,
          "company_id" => company_id,
          "relationship_type_id" => roles["prospect"].id
        }
      }
    end

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [create.(75)])
    assert {:ok, plan} = AgentApi.plan(scope, [create.(73)])
    assert plan["valid"]
    assert {:ok, []} = Person.relationships(scope, lead.id)
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [create.(73)])
    assert {:ok, [%{id: id, role_code: "prospect"}]} = Person.relationships(scope, lead.id)

    unlink = %{
      "key" => "core.person.relationship.unlink",
      "input" => %{"person_id" => lead.id, "relationship_id" => id}
    }

    assert {:ok, plan} = AgentApi.plan(scope, [unlink])
    assert plan["valid"]

    {:ok, _} =
      Bilimbi.Base.Settings.put(
        "authz.agent_writes_enabled",
        false,
        Bilimbi.Base.Settings.Scope.company(73, 41)
      )

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [unlink])
    assert {:ok, [_]} = Person.relationships(scope, lead.id)
  end
end
