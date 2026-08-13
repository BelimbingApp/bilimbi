defmodule BilimbiWeb.SessionController do
  @moduledoc """
  Session boundary for the login LiveView and the sidebar logout.

  The LiveView verifies credentials and hands this controller a short-lived
  signed token (see `BilimbiWeb.UserAuth.sign_login_token/1`); the controller
  performs the actual session write and full navigation, mirroring
  Belimbing's `Session::regenerate()` followed by a redirect to the intended
  URL or landing page.
  """

  use BilimbiWeb, :controller

  alias BilimbiWeb.UserAuth

  def create(conn, %{"login" => %{"_token" => token}}) do
    case UserAuth.verify_login_token(token) do
      {:ok, session_user} ->
        UserAuth.log_in_user(conn, session_user)

      {:error, _reason} ->
        # An expired or forged token restarts the flow honestly rather than
        # failing with a bare 4xx.
        conn
        |> put_flash(:error, gettext("That sign-in expired. Please sign in again."))
        |> redirect(to: ~p"/")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, gettext("That sign-in expired. Please sign in again."))
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
