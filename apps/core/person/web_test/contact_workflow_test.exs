defmodule BilimbiWeb.ContactWorkflowTest do
  use BilimbiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{AgentApi, Authz, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Person
  alias Bilimbi.Core.Company.TestFixtures, as: Companies

  @caps ~w(admin.person.list admin.person.view admin.person.create admin.person.update admin.company.view admin.company.list admin.company.tenant-wide.manage)

  setup do
    signed_in_identity!()
    Person.TestFixtures.create_person_tables!()
    AgentApi.TestFixtures.create_plan_tables!()
    Companies.insert_company!(%{id: 74, code: "vendor", name: "Vendor Ltd"})
    Companies.insert_tenant!(%{id: 42, is_platform_operator: false})
    Companies.insert_company!(%{id: 75, tenant_id: 42, code: "foreign", name: "Foreign Ltd"})
    {:ok, system} = Tenancy.scope(41)
    scope = Authentication.sign_in(system, 91, 73)
    %{scope: scope, system: system}
  end

  test "UI namecard creates a vendor contact without HR, login or grants and supports in-place editing",
       %{conn: conn, scope: scope} do
    grant_capabilities!(@caps)
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts/new")
    refute has_element?(view, "[name='contact[employee_number]']")
    refute has_element?(view, "[name='contact[status]']")
    refute has_element?(view, "#contact-company option[value='75']")

    view
    |> form("#contact-form",
      contact: %{
        full_name: "Vendor Vera",
        company_id: "74",
        title: "Sales",
        email: "vera@vendor.test",
        phone: "+60123"
      }
    )
    |> render_submit()

    {:ok, %{entries: [p]}} = Person.list(scope)
    assert_redirect(view, "/contacts/#{p.id}")
    {:ok, details, _} = conn |> log_in_as() |> live(~p"/contacts/#{p.id}")
    render_hook(details, "save_field", %{"id" => "#{p.id}", "full_name" => "Vera Vendor"})
    assert {:ok, person} = Person.get(scope, p.id)
    assert person.full_name == "Vera Vendor"
    [a] = person.affiliations

    render_hook(details, "save_affiliation", %{
      "id" => "#{a.id}",
      "affiliation-#{a.id}-title" => "Director"
    })

    assert {:ok, %{affiliations: [%{title: "Director"}]}} = Person.get(scope, p.id)
    assert {:ok, []} = Bilimbi.Core.Employee.list_employees(scope, 73)
    assert {:ok, []} = Bilimbi.Core.Employee.list_employees(scope, 74)
    assert {:ok, [%{id: 91}]} = Bilimbi.Core.User.list_users(scope)
  end

  test "forged UI cross-tenant target and revoked capability cannot create contacts", %{
    conn: conn,
    scope: scope
  } do
    grant_capabilities!(@caps)
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts/new")
    render_submit(view, "save", %{"contact" => %{"full_name" => "Stolen", "company_id" => "75"}})
    assert {:ok, %{entries: []}} = Person.list(scope)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, 73, :user, 91, "admin.person.create", false)

    render_submit(view, "save", %{"contact" => %{"full_name" => "Denied", "company_id" => "74"}})
    assert {:ok, %{entries: []}} = Person.list(scope)
  end

  test "discovery schemas and bound plans expose contacts without manufacturing HR facts", %{
    scope: scope
  } do
    grant_capabilities!(@caps)
    assert {:ok, description} = AgentApi.describe(scope, "core.person.contact.create")
    assert description

    op = %{
      "key" => "core.person.contact.create",
      "input" => %{
        "full_name" => "Vera",
        "company_id" => 74,
        "title" => "Sales",
        "email" => "vera@vendor.test"
      }
    }

    assert {:ok, plan} = AgentApi.plan(scope, [op])
    assert plan["valid"]
    assert {:ok, %{entries: []}} = Person.list(scope)
    assert {:ok, result} = AgentApi.commit(scope, plan["plan_code"], [op])
    assert result
    assert {:ok, %{entries: [p]}} = Person.list(scope, search: "vera")

    assert {:ok, %{affiliations: [%{company_id: 74, legacy_employee_id: nil}]}} =
             Person.get(scope, p.id)

    assert {:error, :plan_already_used} = AgentApi.commit(scope, plan["plan_code"], [op])
    assert {:ok, []} = Bilimbi.Core.Employee.list_employees(scope, 73)
    assert {:ok, []} = Bilimbi.Core.Employee.list_employees(scope, 74)
  end

  test "agent plans deny unauthorised and cross-tenant writes, including capability revocation before commit",
       %{scope: scope} do
    grant_capabilities!(@caps)

    op = %{
      "key" => "core.person.contact.create",
      "input" => %{"full_name" => "Vera", "company_id" => 75}
    }

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [op])
    op = put_in(op, ["input", "company_id"], 74)
    {:ok, plan} = AgentApi.plan(scope, [op])
    assert plan["valid"]

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, 73, :user, 91, "admin.person.create", false)

    assert {:error, _} = AgentApi.commit(scope, plan["plan_code"], [op])
    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [op])
    assert {:ok, %{entries: []}} = Person.list(scope)
  end

  test "affiliation updates and unlinks honor the stored target company's agent write switch", %{
    scope: scope
  } do
    grant_capabilities!(@caps)

    {:ok, %{person: person, affiliation: a}} =
      Person.create_contact(scope, 74, %{full_name: "Vera"})

    {:ok, _} =
      Bilimbi.Base.Settings.put(
        "authz.agent_writes_enabled",
        false,
        Bilimbi.Base.Settings.Scope.company(74, 41)
      )

    for key <- ~w(core.person.affiliation.update core.person.affiliation.unlink) do
      input = %{"person_id" => person.id, "affiliation_id" => a.id}

      input =
        if String.ends_with?(key, "update"), do: Map.put(input, "title", "Director"), else: input

      assert {:ok, %{"valid" => false}} =
               AgentApi.plan(scope, [%{"key" => key, "input" => input}])
    end

    assert {:ok, %{affiliations: [%{unlinked_at: nil, title: nil}]}} =
             Person.get(scope, person.id)
  end

  test "read-only contact viewers see facts and cannot forge updates or affiliation writes", %{
    conn: conn,
    system: system
  } do
    grant_capabilities!(~w(admin.person.list admin.person.view))

    {:ok, %{person: person, affiliation: a}} =
      Person.create_contact(system, 74, %{full_name: "Vera", title: "Sales"})

    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts/#{person.id}")
    assert has_element?(view, "#contact-update-forbidden")
    refute has_element?(view, "#contact-edit-full_name")
    refute has_element?(view, "#affiliation-form")
    render_hook(view, "save_field", %{"full_name" => "Forged"})
    render_hook(view, "unlink", %{"id" => "#{a.id}"})

    assert {:ok, %{full_name: "Vera", affiliations: [%{unlinked_at: nil}]}} =
             Person.get(system, person.id)
  end

  test "contact list uses shared catalog columns and URL search without losing tenant boundaries",
       %{conn: conn, system: system} do
    grant_capabilities!(@caps)

    {:ok, _} =
      Person.create_contact(system, 74, %{full_name: "Vendor Vera", email: "vera@vendor.test"})

    {:ok, view, _} = conn |> log_in_as() |> live(~p"/contacts")
    assert has_element?(view, "#contacts tbody a", "Vendor Vera")
    view |> form("#contacts-filters", filters: %{search: "missing"}) |> render_change()
    assert_patch(view)
    assert has_element?(view, "#contacts-empty")
  end
end
