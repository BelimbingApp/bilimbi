defmodule BilimbiWeb.SessionControllerTest do
  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Base.Session
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias BilimbiWeb.UserAuth

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    :ok
  end

  describe "POST /session" do
    test "establishes a durable session from a signed login token and redirects", %{conn: conn} do
      token = UserAuth.sign_login_token(session_user())

      conn = post(conn, ~p"/session", %{"login" => %{"_token" => token}})

      assert redirected_to(conn) == ~p"/dashboard"

      cookie = get_session(conn, "current_user")
      assert cookie["user_id"] == 91
      assert cookie["company_id"] == 73
      assert is_binary(cookie["session_id"])
      refute Map.has_key?(cookie, "name")
      refute Map.has_key?(cookie, "email")
      refute Map.has_key?(cookie, "tenant_id")

      assert {:ok, %Session.Entry{user_id: 91, payload: "{}"}} =
               Session.fetch_session(cookie["session_id"])
    end

    test "returns to the intended URL stored before sign-in", %{conn: conn} do
      token = UserAuth.sign_login_token(session_user())

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{"user_return_to" => "/companies"})
        |> post(~p"/session", %{"login" => %{"_token" => token}})

      assert redirected_to(conn) == "/companies"
    end

    test "rejects a forged token and restarts the flow", %{conn: conn} do
      conn = post(conn, ~p"/session", %{"login" => %{"_token" => "forged"}})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "sign in again"
      refute get_session(conn, "current_user")
    end

    test "rejects a request without a token", %{conn: conn} do
      conn = post(conn, ~p"/session", %{"login" => %{}})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, "current_user")
    end
  end

  describe "DELETE /session" do
    test "deletes the durable session and returns to the sign-in screen", %{conn: conn} do
      conn = log_in_as(conn)
      session_id = get_session(conn, "current_user")["session_id"]
      assert {:ok, %Session.Entry{}} = Session.fetch_session(session_id)

      conn = delete(conn, ~p"/session")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, "current_user")
      assert {:error, :not_found} = Session.fetch_session(session_id)
    end
  end
end
