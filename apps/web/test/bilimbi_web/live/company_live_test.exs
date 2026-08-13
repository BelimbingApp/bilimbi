defmodule BilimbiWeb.CompanyLiveTest do
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

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  describe "Index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies")
    end

    test "redirects away when the actor lacks admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies")
    end

    test "lists only the current tenant's companies", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies td", "Bilimbi Industries")
      refute has_element?(view, "#companies td", "Elsewhere")
      assert has_element?(view, "#nav-admin-company[aria-current='page']")
    end
  end

  describe "Show" do
    test "redirects away when the actor lacks admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73")
    end

    test "renders the company with its users", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "h1", "Bilimbi Industries")
      assert has_element?(view, "#company-users-table td", "Ada Lovelace")
      assert has_element?(view, "#company-employees-table")
    end

    test "redirects away for another tenant's company", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      assert {:error, {:live_redirect, %{to: "/companies"}}} =
               conn |> log_in_as() |> live(~p"/companies/74")
    end

    test "redirects away for a missing company", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      assert {:error, {:live_redirect, %{to: "/companies"}}} =
               conn |> log_in_as() |> live(~p"/companies/9999")
    end
  end
end
