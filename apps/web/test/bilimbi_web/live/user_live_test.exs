defmodule BilimbiWeb.UserLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users")
  end

  test "redirects away when the actor lacks admin.user.list", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/users")
  end

  test "lists only users affiliated with the current tenant", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!("admin.user.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#users td", "Ada Lovelace")
    refute has_element?(view, "#users td", "Grace Hopper")
  end

  test "links each user to their company", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    grant_capabilities!(["admin.user.list", "admin.company.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#users a[href='/companies/73']", "Bilimbi Industries")
  end
end
