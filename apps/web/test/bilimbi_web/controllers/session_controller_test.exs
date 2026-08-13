defmodule BilimbiWeb.SessionControllerTest do
  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias BilimbiWeb.UserAuth

  setup do
    CompanyFixtures.create_company_identity_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    :ok
  end

  describe "POST /session" do
    test "establishes the session from a signed login token and redirects", %{conn: conn} do
      token = UserAuth.sign_login_token(session_user())

      conn = post(conn, ~p"/session", %{"login" => %{"_token" => token}})

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_session(conn, "current_user")["user_id"] == 91
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
    test "logs out and returns to the sign-in screen", %{conn: conn} do
      conn =
        conn
        |> log_in_as()
        |> delete(~p"/session")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, "current_user")
    end
  end
end
