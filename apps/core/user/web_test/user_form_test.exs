defmodule BilimbiWeb.UserFormTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    :ok
  end

  describe "new" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/new")
    end

    test "redirects away when the actor lacks admin.user.create", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/users/new")
    end

    test "validates required fields before calling the domain", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})
      grant_capabilities!(["admin.user.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/new")

      assert has_element?(view, "#user-back[href='/users']", "Back")
      assert has_element?(view, "#user-cancel[href='/users']", "Cancel")

      view |> form("#user-form", user: %{name: "", email: ""}) |> render_submit()

      assert has_element?(view, "#user-form", "can't be blank")
    end

    test "creates a user in a tenant company and lands on their page", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})
      grant_capabilities!(["admin.user.create", "admin.user.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/new")

      view
      |> form("#user-form",
        user: %{
          name: "Grace Hopper",
          email: "grace@example.com",
          password: "correct horse battery",
          company_id: "73"
        }
      )
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"^/users/\d+$"

      {:ok, view, _html} = conn |> log_in_as() |> live(path)
      assert has_element?(view, "h1", "Grace Hopper")
      assert has_element?(view, "#app-content", "unverified")
    end

    test "surfaces domain validation errors on the form", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})
      UserFixtures.insert_user!(%{id: 92, company_id: 73, email: "taken@example.com"})
      grant_capabilities!(["admin.user.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/new")

      view
      |> form("#user-form",
        user: %{
          name: "Grace Hopper",
          email: "taken@example.com",
          password: "correct horse battery",
          company_id: "73"
        }
      )
      |> render_submit()

      assert has_element?(view, "#user-form p.text-danger-ink", "has already been taken")
    end
  end

  test "the edit route is retired: a user's facts change on their record page", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    grant_capabilities!(["admin.user.update", "admin.user.view"])

    retired = "/users/91/edit"
    assert Phoenix.Router.route_info(BilimbiWeb.Router, "GET", retired, "localhost") == :error
    assert conn |> log_in_as() |> get(retired) |> Map.fetch!(:status) == 404

    {:ok, show, _html} = conn |> log_in_as() |> live(~p"/users/91")
    assert has_element?(show, "#user-name[phx-hook='InlineEdit']")
  end
end
