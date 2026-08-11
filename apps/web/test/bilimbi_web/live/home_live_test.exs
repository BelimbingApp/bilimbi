defmodule BilimbiWeb.HomeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Bilimbi.Core.CompanyFixtures
  import Phoenix.LiveViewTest

  setup do
    create_company_identity_tables!()
    :ok
  end

  test "presents the explicit platform-operator primary company", %{conn: conn} do
    insert_tenant!()

    insert_company!(%{
      name: "Bilimbi Operations",
      legal_name: "Bilimbi Operations Sdn. Bhd.",
      code: "bilimbi_operations"
    })

    assign_primary_company!()

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#platform-overview")

    assert has_element?(
             view,
             "#platform-operator-company[data-company-id='73'][data-tenant-id='41']"
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
