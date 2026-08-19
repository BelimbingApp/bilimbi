defmodule BilimbiWeb.UserShowTest do
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
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/91")
  end

  test "redirects away when the actor lacks admin.user.view", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/users/91")
  end

  test "shows the user with company link and verification state", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    assert has_element?(view, "h1", "Grace Hopper")
    assert has_element?(view, "#user-back[href='/users']", "Back")
    assert has_element?(view, "a[href='/companies/73']", "Bilimbi Industries")
    assert has_element?(view, "#app-content", "unverified")
    refute has_element?(view, "#user-edit")
    refute has_element?(view, "#user-danger")
  end

  test "hides the destructive action without admin.user.delete", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    refute has_element?(view, "#user-delete")
    assert has_element?(view, "#user-edit")
  end

  test "redirects to the index for a user outside the tenant", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 93,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    assert {:error, {:live_redirect, %{to: "/users"}}} =
             conn |> log_in_as() |> live(~p"/users/93")
  end

  test "deletes another user with admin.user.delete", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.list", "admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    view |> element("#user-delete") |> render_click()

    assert_redirected_with_flash(view, "/users")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")
    refute has_element?(view, "#users td", "Grace Hopper")
  end

  test "shows a user whose company is archived, matching index visibility", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      code: "archived",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 76,
      name: "Ada Archived",
      email: "archived@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/95")

    assert has_element?(view, "h1", "Ada Archived")
    refute has_element?(view, "#app-content", "does not exist in this workspace")
  end

  test "refuses to delete a user whose company is archived", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      code: "archived",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 76,
      name: "Ada Archived",
      email: "archived@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/95")

    view |> element("#user-delete") |> render_click()

    assert has_element?(view, "#flash-group", "while their company is archived")
  end

  test "refuses to delete the signed-in account", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    grant_capabilities!(["admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

    view |> element("#user-delete") |> render_click()

    assert has_element?(view, "#flash-group", "cannot delete your own account")
  end

  test "shows impersonate action when actor has admin.user.impersonate", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Admin"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Target",
      email: "target@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.impersonate"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    assert has_element?(view, "#user-impersonate[href='/admin/impersonate/92']", "Impersonate")

    # When viewing own profile, impersonate button is hidden
    {:ok, own_view, _html} = conn |> log_in_as() |> live(~p"/users/91")
    refute has_element?(own_view, "#user-impersonate")
  end

  defp assert_redirected_with_flash(view, to) do
    assert {path, _flash} = assert_redirect(view)
    assert path == to
  end
end
