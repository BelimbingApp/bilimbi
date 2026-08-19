defmodule BilimbiWeb.PlatformOperatorSetupLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()
    CompanyFixtures.create_external_access_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      code: "bilimbi_industries"
    })

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 75,
      name: "Other User",
      email: "other@example.com"
    })

    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/setup/platform-operator")
  end

  test "redirects away when the actor lacks admin.company.update", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/setup/platform-operator")
  end

  test "redirects away when the current tenant is not the platform operator", %{conn: conn} do
    grant_capabilities!(["admin.company.update"],
      tenant_id: 42,
      company_id: 75,
      user_id: 92
    )

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             conn
             |> log_in_as(session_user(%{"user_id" => 92, "company_id" => 75}))
             |> live(~p"/setup/platform-operator")
  end

  test "redirects to the primary company when one is already designated", %{conn: conn} do
    CompanyFixtures.assign_primary_company!(41, 73)
    grant_capabilities!(["admin.company.update", "admin.company.view"])

    assert {:error, {:live_redirect, %{to: "/companies/73"}}} =
             conn |> log_in_as() |> live(~p"/setup/platform-operator")
  end

  test "designates an existing operator-tenant company as primary", %{conn: conn} do
    grant_capabilities!(["admin.company.update", "admin.company.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/setup/platform-operator")

    assert has_element?(view, "#platform-operator-select")
    refute has_element?(view, "#platform-operator-company option", "Elsewhere")

    view
    |> form("#platform-operator-designate-form", company_id: "73")
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/companies/73"
    assert flash["info"] =~ "designated successfully"

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, :unchanged} = Company.assign_primary_company(scope, 73)
  end

  test "refuses to designate another tenant's company", %{conn: conn} do
    grant_capabilities!(["admin.company.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/setup/platform-operator")

    html = render_submit(view, "designate", %{"company_id" => "75"})
    assert html =~ "not in this workspace"

    assert {:error, :not_provisioned} = Company.platform_operator_company()
  end

  test "creates a primary company through the domain API", %{conn: conn} do
    grant_capabilities!(["admin.company.update", "admin.company.view", "admin.company.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/setup/platform-operator")

    view |> element("#platform-operator-switch-create") |> render_click()

    view
    |> form("#platform-operator-create-form", company: %{name: "Operator Co"})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path =~ ~r"^/companies/\d+$"
    assert flash["info"] =~ "created successfully"

    assert {:ok, %Company.Summary{name: "Operator Co", code: "operator_co"}} =
             Company.platform_operator_company()
  end
end
