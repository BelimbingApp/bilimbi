defmodule BilimbiWeb.ArchivedCompanySessionTest do
  @moduledoc """
  An archived company's accounts cannot sign in, be impersonated, or keep a
  session. The login edge refuses them on every request, and archiving ends
  their durable sessions as soon as it commits.
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

  test "archiving ends the company's sessions and later sign-in is refused", %{
    conn: conn,
    scope: scope,
    member: member
  } do
    grant_capabilities!(["admin.company.update", "admin.company.tenant-wide.manage"])

    member_conn = log_in_as(conn, %{"user_id" => member.id, "company_id" => 74})
    assert {:ok, _view, _html} = live(member_conn, ~p"/dashboard")

    admin_conn = log_in_as(build_conn())
    admin_session = Plug.Conn.get_session(admin_conn, "current_user")["session_id"]

    {:ok, _company} =
      Company.archive_company(Authentication.sign_in(scope, 91, 73), 74, reason: "closed")

    _ = :sys.get_state(BilimbiWeb.CompanySessionTermination)

    assert [%Session.Summary{id: ^admin_session}] = Session.list_sessions()
    assert {:error, {:redirect, %{to: "/"}}} = live(member_conn, ~p"/dashboard")

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

    # The status alone decides, whether or not the termination ran.
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

  test "ending sessions is refused for a company that is not archived", %{
    conn: conn,
    scope: scope,
    member: member
  } do
    log_in_as(conn, %{"user_id" => member.id, "company_id" => 74})

    assert {:error, :company_not_archived} = User.terminate_company_sessions(scope, 74)
    assert [%Session.Summary{user_id: user_id}] = Session.list_sessions()
    assert user_id == member.id
  end

  # The status the lifecycle writes, without its audit and capability
  # preconditions, for tests about the login edge alone.
  defp archive_status!(company_id) do
    Ecto.Adapters.SQL.query!(Repo, "UPDATE companies SET status = 'archived' WHERE id = $1", [
      company_id
    ])
  end
end
