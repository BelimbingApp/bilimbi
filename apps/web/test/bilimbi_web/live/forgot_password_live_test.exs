defmodule BilimbiWeb.ForgotPasswordLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Bilimbi.Core.Company

  setup do
    Bilimbi.Core.User.TestFixtures.create_user_tables!()
    set_swoosh_global()
  end

  test "sends a reset email and shows the neutral confirmation for an existing account", %{
    conn: conn
  } do
    register_user!()
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    view
    |> form("#forgot-form", forgot: %{email: "ada@example.com"})
    |> render_submit()

    assert has_element?(
             view,
             "#forgot-confirmation",
             "A reset link will be sent if the account exists."
           )

    assert_email_sent(
      to: {"Ada Lovelace", "ada@example.com"},
      subject: "Reset your Bilimbi password",
      text_body: ~r{/reset-password/[^?]+\?email=ada%40example.com}
    )
  end

  test "shows the same neutral confirmation for an unknown account", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    view
    |> form("#forgot-form", forgot: %{email: "unknown@example.com"})
    |> render_submit()

    assert has_element?(
             view,
             "#forgot-confirmation",
             "A reset link will be sent if the account exists."
           )

    refute_email_sent()
  end

  test "validates the email field", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    html =
      view
      |> form("#forgot-form", forgot: %{email: "not-an-email"})
      |> render_submit()

    assert html =~ "must be a valid email address"
  end

  defp register_user! do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, user} =
      Bilimbi.Core.User.register_user(scope, 73, %{
        name: "Ada Lovelace",
        email: "ada@example.com",
        password: "old-password"
      })

    user
  end
end
