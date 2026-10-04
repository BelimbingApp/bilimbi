defmodule BilimbiWeb.SessionActivityTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup %{conn: conn} do
    UserFixtures.create_user_tables!()
    AuditFixtures.create_audit_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    assert {:ok, _} = Settings.put("session.lifetime_minutes", 3 * 24 * 60)
    conn = log_in_as(conn)
    session_id = get_session(conn, "current_user")["session_id"]
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    %{conn: conn, view: view, session_id: session_id}
  end

  test "ordinary events preserve an active session across expiry sweeps", %{
    view: view,
    session_id: session_id
  } do
    for _day <- 1..2 do
      age_session(session_id, System.system_time(:second) - 2 * 86_400)
      audit_count = Repo.aggregate(MutationSchema, :count)
      before_event = System.system_time(:second)

      render_click(view, "toggle-layout-edit")

      assert {:ok, entry} = Session.fetch_session(session_id)
      assert entry.last_activity >= before_event
      assert Repo.aggregate(MutationSchema, :count) == audit_count
      assert Session.prune_expired(System.system_time(:second) - 3 * 86_400) == 0
      assert {:ok, _entry} = Session.fetch_session(session_id)
    end
  end

  test "component-targeted events preserve activity without audit writes", %{
    view: view,
    session_id: session_id
  } do
    for open? <- [true, false] do
      age_session(session_id, System.system_time(:second) - 2 * 86_400)
      audit_count = Repo.aggregate(MutationSchema, :count)
      before_event = System.system_time(:second)

      view |> element("#app-notifications-bell") |> render_click()
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#app-notifications-bell[aria-expanded='#{open?}']")
      assert {:ok, entry} = Session.fetch_session(session_id)
      assert entry.last_activity >= before_event
      assert Repo.aggregate(MutationSchema, :count) == audit_count
      assert Session.prune_expired(System.system_time(:second) - 3 * 86_400) == 0
      assert {:ok, _entry} = Session.fetch_session(session_id)
    end
  end

  test "events within the configured interval do not rewrite activity", %{
    view: view,
    session_id: session_id
  } do
    recent = System.system_time(:second) - 30
    age_session(session_id, recent)
    render_click(view, "toggle-layout-edit")
    assert {:ok, %{last_activity: ^recent}} = Session.fetch_session(session_id)
    view |> element("#app-notifications-bell") |> render_click()
    _ = :sys.get_state(view.pid)
    assert {:ok, %{last_activity: ^recent}} = Session.fetch_session(session_id)
  end

  test "live patches and intercepted shell events refresh activity", %{
    view: view,
    session_id: session_id
  } do
    for interact <- [
          fn -> render_patch(view, "/dashboard?search=activity") end,
          fn -> render_hook(view, "shell:preference", %{}) end
        ] do
      age_session(session_id, System.system_time(:second) - 10 * 60)
      before_event = System.system_time(:second)
      interact.()
      assert {:ok, entry} = Session.fetch_session(session_id)
      assert entry.last_activity >= before_event
    end
  end

  test "activity does not recreate a terminated session", %{view: view, session_id: session_id} do
    assert :ok = Session.delete_session(session_id)

    assert {:error, {:redirect, %{to: "/"}}} = render_click(view, "toggle-layout-edit")
    assert {:error, :not_found} = Session.fetch_session(session_id)
  end

  test "component activity does not recreate a terminated session", %{
    view: view,
    session_id: session_id
  } do
    assert :ok = Session.delete_session(session_id)

    assert {:error, {:redirect, %{to: "/"}}} =
             view |> element("#app-notifications-bell") |> render_click()

    assert {:error, :not_found} = Session.fetch_session(session_id)
  end

  defp age_session(session_id, last_activity) do
    assert {:ok, entry} = Session.fetch_session(session_id)

    assert {:ok, _entry} =
             Session.put_session(session_id, entry.payload, %{
               user_id: entry.user_id,
               last_activity: last_activity
             })
  end
end
