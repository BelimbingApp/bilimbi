defmodule BilimbiWeb.HomeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures

  setup do
    TestFixtures.create_company_identity_tables!()
    :ok
  end

  test "presents the explicit platform-operator primary company", %{conn: conn} do
    assert {:ok, identity} =
             Company.provision_platform_operator("Platform operator", %{
               name: "Bilimbi Operations",
               legal_name: "Bilimbi Operations Sdn. Bhd.",
               code: "bilimbi_operations"
             })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#platform-overview")

    assert has_element?(
             view,
             "#platform-operator-company[data-company-id='#{identity.company.id}']" <>
               "[data-tenant-id='#{identity.tenant.id}']"
           )

    assert has_element?(view, "#company-name", "Bilimbi Operations Sdn. Bhd.")
    assert has_element?(view, "#company-code", "bilimbi_operations")
    assert has_element?(view, "#company-status", "active")
  end

  test "shows an actionable setup state when explicit identity is absent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#company-setup-state[data-state='not_provisioned']")
    refute has_element?(view, "#platform-operator-company")
  end
end
