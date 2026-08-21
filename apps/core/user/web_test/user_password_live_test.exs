defmodule BilimbiWeb.UserPasswordLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Password
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com",
      password_hash: UserFixtures.password_hash("current-secret-123")
    })

    :ok
  end

  defp open(conn), do: conn |> log_in_as() |> live(~p"/settings/password")

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/settings/password")
  end

  test "renders password form with self-service layout", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#password-form")
    assert has_element?(view, "input[name='password_change[current_password]']")
    assert has_element?(view, "input[name='password_change[password]']")
    assert has_element?(view, "input[name='password_change[password_confirmation]']")
  end

  test "validates required fields and password length", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    result =
      view
      |> form("#password-form", %{
        "password_change" => %{
          "current_password" => "current-secret-123",
          "password" => "short",
          "password_confirmation" => "mismatch"
        }
      })
      |> render_change()

    assert result =~ "should be at least 8 character"
    assert result =~ "does not match password"
  end

  test "shows error when current password is wrong", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    result =
      view
      |> form("#password-form", %{
        "password_change" => %{
          "current_password" => "wrong-password",
          "password" => "new-secure-password-456",
          "password_confirmation" => "new-secure-password-456"
        }
      })
      |> render_submit()

    assert result =~ "is incorrect"
  end

  test "successfully updates password with valid current credentials", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#password-form", %{
      "password_change" => %{
        "current_password" => "current-secret-123",
        "password" => "new-secure-password-456",
        "password_confirmation" => "new-secure-password-456"
      }
    })
    |> render_submit()

    assert has_element?(view, "#flash-info", "Password updated successfully.")

    # Verify password hash was updated in database
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, user} = User.get_tenant_user(scope, 91)
    stored_hash = UserFixtures.stored_password(user.id)
    assert Password.valid?("new-secure-password-456", stored_hash)
    refute Password.valid?("current-secret-123", stored_hash)
  end
end
