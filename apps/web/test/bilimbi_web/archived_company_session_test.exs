defmodule BilimbiWeb.ArchivedCompanySessionTest do
  @moduledoc """
  An archived company's accounts cannot sign in, be impersonated, or keep a
  session. The login edge reads the company's status on every request and
  LiveView event, so the refusal follows the archive without anything stored.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @password "c0rrect-horse-battery"

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.assign_primary_company!(41, 73)

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Closing branch",
      code: "closing_branch"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    {:ok, scope} = Tenancy.scope(41)

    {:ok, member} =
      User.register_user(scope, 74, %{
        name: "Grace Hopper",
        email: "grace@example.com",
        password: @password
      })

    %{scope: scope, member: member}
  end

  test "archiving the company refuses its accounts at the login form", %{scope: scope} do
    grant_capabilities!(["admin.company.update", "admin.company.tenant-wide.manage"])

    {:ok, _company} =
      Company.archive_company(Authentication.sign_in(scope, 91, 73), 74, reason: "closed")

    {:ok, view, _html} = live(build_conn(), ~p"/")

    view
    |> form("#login-form", login: %{email: "grace@example.com", password: @password})
    |> render_submit()

    assert has_element?(
             view,
             "#login-form-error",
             "This account's company is archived, so it can no longer sign in."
           )

    refute has_element?(view, "#login-form[phx-trigger-action]")
  end

  test "a session opened before the archive is refused on its next request", %{
    conn: conn,
    member: member
  } do
    member_conn = log_in_as(conn, %{"user_id" => member.id, "company_id" => 74})
    assert {:ok, _view, _html} = live(member_conn, ~p"/dashboard")

    archive_status!(74)

    assert {:error, {:redirect, %{to: "/"}}} = live(member_conn, ~p"/dashboard")
    assert redirected_to(get(member_conn, ~p"/dashboard")) == ~p"/"
  end

  test "an archived company's account cannot be impersonated", %{conn: conn, member: member} do
    grant_capabilities!(["admin.user.list", "admin.user.impersonate"])
    archive_status!(74)

    admin_conn = log_in_as(conn)
    resp = post(admin_conn, ~p"/admin/impersonate/#{member.id}")

    refute redirected_to(resp) == ~p"/dashboard"
    assert [%Session.Summary{user_id: 91}] = Session.list_sessions()
  end

  # The status the lifecycle writes, without its audit and capability
  # preconditions, for tests about the login edge alone.
  defp archive_status!(company_id) do
    Ecto.Adapters.SQL.query!(Repo, "UPDATE companies SET status = 'archived' WHERE id = $1", [
      company_id
    ])
  end
end
