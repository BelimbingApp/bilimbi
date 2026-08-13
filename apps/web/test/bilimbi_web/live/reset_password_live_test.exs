defmodule BilimbiWeb.ResetPasswordLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  setup do
    Bilimbi.Core.User.TestFixtures.create_user_tables!()
    set_swoosh_global()
    register_user!()
    :ok
  end

  test "a valid token changes the password and redirects to sign in", %{conn: conn} do
    token = request_token!(conn)

    {:ok, view, _html} =
      live(conn, ~p"/reset-password/#{token}?#{[email: "ada@example.com"]}")

    result =
      view
      |> form("#reset-form",
        reset: %{
          email: "ada@example.com",
          password: "new-password",
          password_confirmation: "new-password"
        }
      )
      |> render_submit()

    assert {:ok, _login_view, html} = follow_redirect(result, conn, ~p"/")
    assert html =~ "Your password has been reset."
    assert {:ok, _user} = User.authenticate("ada@example.com", "new-password")
    assert {:error, :invalid_credentials} = User.authenticate("ada@example.com", "old-password")
  end

  test "an invalid token reports the error on the email field", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/reset-password/bad-token?#{[email: "ada@example.com"]}")

    view
    |> form("#reset-form",
      reset: %{
        email: "ada@example.com",
        password: "new-password",
        password_confirmation: "new-password"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             "#reset-email + p",
             "The password reset link is invalid or has expired."
           )
  end

  test "requires matching password confirmation", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/reset-password/token?#{[email: "ada@example.com"]}")

    html =
      view
      |> form("#reset-form",
        reset: %{
          email: "ada@example.com",
          password: "new-password",
          password_confirmation: "different-password"
        }
      )
      |> render_submit()

    assert html =~ "does not match confirmation"
  end

  defp request_token!(conn) do
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    view
    |> form("#forgot-form", forgot: %{email: "ada@example.com"})
    |> render_submit()

    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/reset-password/([^?\s]+)}, email.text_body)
      Process.put(:reset_token, token)
      true
    end)

    Process.delete(:reset_token)
  end

  defp register_user! do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, user} =
      User.register_user(scope, 73, %{
        name: "Ada Lovelace",
        email: "ada@example.com",
        password: "old-password"
      })

    user
  end
end
