defmodule BilimbiWeb.AuthenticatedSessionTest do
  @moduledoc """
  The host's durable-session and live-navigation guards, exercised through the
  landing page every signed-in account can reach.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41, name: "Bilimbi local development"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.assign_primary_company!(41, 73)
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "rejects a durable session that exceeded the configured idle lifetime", %{conn: conn} do
    session_id = "expired-session"
    old_activity = System.system_time(:second) - 120 * 60 - 1

    {:ok, _entry} =
      Session.put_session(session_id, "{}", %{user_id: 91, last_activity: old_activity})

    conn =
      Phoenix.ConnTest.init_test_session(conn, %{
        "current_user" => %{"session_id" => session_id, "user_id" => 91, "company_id" => 73}
      })

    assert {:error, {:redirect, %{to: "/", flash: %{"session_expired" => "expired"}}}} =
             live(conn, ~p"/dashboard")

    conn = get(conn, ~p"/dashboard")
    assert redirected_to(conn) == ~p"/"

    assert html_response(get(recycle(conn), ~p"/"), 200) =~
             "Your session expired. Sign in again to continue."
  end

  test "authentication honors changes to the idle lifetime", %{conn: conn} do
    conn = log_in_as(conn)
    session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
    old_activity = System.system_time(:second) - 5 * 60

    assert {:ok, 10} = Settings.put("session.lifetime_minutes", 10)

    assert {:ok, _} =
             Session.put_session(session_id, "{}", user_id: 91, last_activity: old_activity)

    assert conn |> get(~p"/dashboard") |> html_response(200)

    # Restore the same inactivity after the accepted request refreshed it.
    assert {:ok, _} =
             Session.put_session(session_id, "{}", user_id: 91, last_activity: old_activity)

    assert {:ok, 1} = Settings.put("session.lifetime_minutes", 1)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")

    assert {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")
    assert has_element?(view, "#dashboard-current-company")
  end

  test "scheduled expiry rereads the lifetime and preserves active sessions" do
    now = System.system_time(:second)

    execution = %Bilimbi.Base.Queue.Execution{
      job_id: 1,
      attempt: 1,
      max_attempts: 5,
      queue: "default"
    }

    for {id, activity} <- [{"old", now - 900}, {"recent", now - 300}, {"active", now}] do
      assert {:ok, _} = Session.put_session(id, "opaque", last_activity: activity)
    end

    assert {:ok, 10} = Settings.put("session.lifetime_minutes", 10)
    assert :ok = Session.ExpiryWorker.handle_scheduled_job(%{}, execution)
    assert {:error, :not_found} = Session.fetch_session("old")
    assert {:ok, %{last_activity: activity}} = Session.fetch_session("recent")
    assert activity == now - 300
    assert {:ok, %{last_activity: ^now}} = Session.fetch_session("active")

    assert {:ok, 1} = Settings.put("session.lifetime_minutes", 1)
    assert :ok = Session.ExpiryWorker.handle_scheduled_job(%{}, execution)
    assert {:error, :not_found} = Session.fetch_session("recent")
    assert {:ok, %{last_activity: ^now}} = Session.fetch_session("active")
  end

  test "initial HTTP render resolves the durable session only once", %{conn: conn} do
    conn = log_in_as(conn)
    session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
    owner = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      Bilimbi.Base.Repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, {owner, session_id} ->
        # Activity writes also read rows for audit capture, using an activity cutoff.
        if self() == owner and metadata.source == "sessions" and
             match?({:ok, %{command: :select}}, metadata.result) and
             metadata.params == [session_id] do
          send(owner, :session_read)
        end
      end,
      {owner, session_id}
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    conn = get(conn, ~p"/dashboard")
    assert html_response(conn, 200)
    assert_receive :session_read
    refute_receive :session_read

    # Connecting must revalidate, even if the initial HTML was authenticated.
    :ok = Session.delete_session(session_id)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn)
  end

  test "module pages and dashboard support navigation without an HTTP reload", %{conn: conn} do
    {:ok, profile, _html} = conn |> log_in_as() |> live(~p"/settings/profile")
    assert has_element?(profile, "#app-shell")
    assert {:ok, appearance, _html} = live_redirect(profile, to: "/settings/appearance")
    assert {:ok, dashboard, _html} = live_redirect(appearance, to: "/dashboard")
    assert has_element?(dashboard, "#dashboard-current-company")
  end

  test "live navigation denies a destination capability before mounting it", %{conn: conn} do
    {:ok, dashboard, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live_redirect(dashboard, to: "/users/new")
  end

  test "live navigation rechecks a terminated durable session", %{conn: conn} do
    conn = log_in_as(conn)
    {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
    :ok = Session.delete_session(Plug.Conn.get_session(conn, "current_user")["session_id"])

    assert {:error, {:redirect, %{to: "/"}}} =
             live_redirect(dashboard, to: "/settings/profile")
  end

  test "drops authentication when the live user is gone", %{conn: conn} do
    conn = log_in_as(conn)
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "DELETE FROM users WHERE id = 91", [])

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "drops authentication when the durable session is terminated", %{conn: conn} do
    conn = log_in_as(conn)
    session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
    :ok = Session.delete_session(session_id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end
end
