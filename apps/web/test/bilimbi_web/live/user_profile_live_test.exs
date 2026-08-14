defmodule BilimbiWeb.UserProfileLiveTest do
  @moduledoc """
  The signed-in account's own profile.

  The assertion that matters most is the one about identity: this screen calls
  an admin-shaped API, so it must edit the session's account and no other.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @landing "ui.landing_menu_id"

  setup do
    UserFixtures.create_user_tables!()
    SettingsFixtures.create_settings_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    :ok
  end

  defp open(conn), do: conn |> log_in_as() |> live(~p"/settings/profile")

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/settings/profile")
  end

  test "needs no capability beyond being signed in", %{conn: conn} do
    # Belimbing guards this with authentication alone: it is your own account,
    # not an administrative screen.
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#profile-form")
    assert has_element?(view, "input[name='profile[name]'][value='Ada Lovelace']")
  end

  test "saves name and email", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#profile-form", %{
      "profile" => %{"name" => "Ada King", "email" => "ada.king@example.com"}
    })
    |> render_submit()

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, user} = User.get_tenant_user(scope, 91)
    assert user.name == "Ada King"
    assert user.email == "ada.king@example.com"

    # And the form shows what was saved. Asserting only the database missed a
    # real defect: `current_scope.user` is built at mount and no write
    # refreshes it, so reloading the form from the session redisplayed the old
    # values -- a save that looked to the user like it had silently failed.
    assert has_element?(view, "input[name='profile[name]'][value='Ada King']")
    assert has_element?(view, "input[name='profile[email]'][value='ada.king@example.com']")
  end

  test "ignores a user id smuggled through the form", %{conn: conn} do
    # `User.update_user/4` is admin-shaped and will edit anyone in the tenant.
    # This screen must take the id from the session and nowhere else, or a
    # self-service page becomes an unaudited admin edit with no capability
    # check anywhere in its path.
    {:ok, view, _html} = open(conn)

    # Submitted as a raw event rather than through `form/3`: the form does not
    # render an id field, so the harness would refuse to send one. The threat
    # is a crafted socket message, not a page the user can fill in.
    render_submit(view, "save", %{
      "profile" => %{
        "id" => "92",
        "user_id" => "92",
        "name" => "Renamed",
        "email" => "renamed@example.com"
      }
    })

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, other} = User.get_tenant_user(scope, 92)
    assert other.name == "Grace Hopper"

    assert {:ok, mine} = User.get_tenant_user(scope, 91)
    assert mine.name == "Renamed"
  end

  test "warns that a changed email must be verified again", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#profile-form", %{"profile" => %{"name" => "Ada Lovelace", "email" => "new@x.com"}})
    |> render_submit()

    # The domain clears email_verified_at; saying only "saved" would hide a
    # consequence the user did not ask for.
    #
    # Asserted on the flash, not the page: my first version matched
    # "needs verifying" and passed against the standing help text in the form,
    # which says the same thing whether or not anything was saved.
    assert has_element?(view, "#flash-info", "unverified until you confirm it")
  end

  test "does not warn when the email is unchanged", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#profile-form", %{
      "profile" => %{"name" => "Ada K", "email" => "ada@example.com"}
    })
    |> render_submit()

    refute has_element?(view, "#flash-info", "unverified until you confirm it")
    assert has_element?(view, "#flash-info", "Profile saved.")
  end

  test "offers only landing pages this actor can open", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # Dashboard is reachable by anyone signed in; Companies needs a capability
    # this account does not hold, so it must not be offerable as a landing
    # page — pinning one would redirect the user out on every sign-in.
    assert has_element?(view, "select[name='profile[landing_menu_id]'] option[value='dashboard']")

    refute has_element?(
             view,
             "select[name='profile[landing_menu_id]'] option[value='admin.company']"
           )
  end

  test "rejects a landing page the actor cannot open", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # Raw event again: the select cannot hold an option it never rendered, so
    # a form submission cannot express this. A crafted message can.
    html =
      render_submit(view, "save", %{
        "profile" => %{
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "landing_menu_id" => "admin.company"
        }
      })

    assert html =~ "is not a page you can open"
    assert Settings.get(@landing, Settings.Scope.user(91, 73, 41)) in [nil, ""]
  end

  test "clearing the landing page removes the override rather than pinning it", %{conn: conn} do
    scope = Settings.Scope.user(91, 73, 41)
    assert {:ok, "dashboard"} = Settings.put(@landing, "dashboard", scope)

    {:ok, view, _html} = open(conn)

    view
    |> form("#profile-form", %{
      "profile" => %{
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "landing_menu_id" => ""
      }
    })
    |> render_submit()

    # Not `== ""`: an empty override would shadow the default forever.
    refute Settings.overridden?(@landing, scope)
  end
end
