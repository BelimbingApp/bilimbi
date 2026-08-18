defmodule BilimbiWeb.ImpersonationControllerTest do
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

    insert_user!(%{id: 91, company_id: 73, name: "Admin User", email: "admin@example.com"})
    insert_user!(%{id: 92, company_id: 73, name: "Target User", email: "target@example.com"})
    insert_user!(%{id: 93, company_id: 74, name: "Foreign User", email: "foreign@example.com"})

    :ok
  end

  test "starts and leaves impersonation with status bar updates", %{conn: conn} do
    grant_capabilities!(["admin.user.list", "admin.user.impersonate"])

    # 1. Sign in as Admin User
    authed_conn = conn |> log_in_as(%{"user_id" => 91, "company_id" => 73})

    # 2. Impersonate Target User
    resp_conn = post(authed_conn, ~p"/admin/impersonate/92")
    assert redirected_to(resp_conn) == ~p"/dashboard"

    # 3. Mount LiveView on dashboard to verify impersonation state and status bar
    {:ok, view, html} = live(resp_conn, ~p"/dashboard")
    assert html =~ "Viewing as Target User"
    assert has_element?(view, "#app-impersonation-stop")

    # 4. Stop impersonation
    leave_conn = post(resp_conn, ~p"/admin/impersonate/leave")
    assert redirected_to(leave_conn) == ~p"/dashboard"

    # 5. Verify back to Admin User and no impersonation in status bar
    {:ok, admin_view, admin_html} = live(leave_conn, ~p"/dashboard")
    refute admin_html =~ "Viewing as"
    refute has_element?(admin_view, "#app-impersonation-stop")
  end

  test "refuses to impersonate self", %{conn: conn} do
    grant_capabilities!(["admin.user.list", "admin.user.impersonate"])

    authed_conn = conn |> log_in_as(%{"user_id" => 91, "company_id" => 73})
    resp_conn = post(authed_conn, ~p"/admin/impersonate/91")

    assert redirected_to(resp_conn) == ~p"/users"
    assert Phoenix.Flash.get(resp_conn.assigns.flash, :error) =~ "cannot impersonate yourself"
  end

  test "refuses nested impersonation while already impersonating", %{conn: conn} do
    insert_user!(%{id: 94, company_id: 73, name: "Another User", email: "another@example.com"})
    grant_capabilities!(["admin.user.list", "admin.user.impersonate"])
    grant_capabilities!(["admin.user.list", "admin.user.impersonate"], user_id: 92)

    authed_conn = conn |> log_in_as(%{"user_id" => 91, "company_id" => 73})
    resp_conn = post(authed_conn, ~p"/admin/impersonate/92")
    assert redirected_to(resp_conn) == ~p"/dashboard"

    # Attempt second impersonation
    nested_conn = post(resp_conn, ~p"/admin/impersonate/94")
    assert redirected_to(nested_conn) == ~p"/dashboard"

    assert Phoenix.Flash.get(nested_conn.assigns.flash, :error) =~
             "Cannot impersonate while impersonating"
  end

  test "denies impersonation without admin.user.impersonate capability", %{conn: conn} do
    grant_capabilities!(["admin.user.list"])

    authed_conn = conn |> log_in_as(%{"user_id" => 91, "company_id" => 73})
    resp_conn = post(authed_conn, ~p"/admin/impersonate/92")

    assert redirected_to(resp_conn) == ~p"/dashboard"
    assert Phoenix.Flash.get(resp_conn.assigns.flash, :error) =~ "You do not have access"
  end

  test "refuses impersonation of users in another tenant", %{conn: conn} do
    grant_capabilities!(["admin.user.list", "admin.user.impersonate"])

    authed_conn = conn |> log_in_as(%{"user_id" => 91, "company_id" => 73})
    resp_conn = post(authed_conn, ~p"/admin/impersonate/93")

    assert redirected_to(resp_conn) == ~p"/users"
    assert Phoenix.Flash.get(resp_conn.assigns.flash, :error) =~ "Unable to find that user"
  end

  defp insert_user!(attributes) do
    id = Map.fetch!(attributes, :id)

    attributes
    |> Map.put_new(:password_hash, "not-used")
    |> Map.put_new(:email, "user-#{id}@example.com")
    |> UserFixtures.insert_user!()
  end
end
