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

  describe "edit" do
    test "redirects away when the actor lacks admin.user.update", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/users/91/edit")
    end

    test "prefills the form and never offers a password field", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
      grant_capabilities!(["admin.user.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91/edit")

      assert has_element?(view, "#user-name[value='Ada Lovelace']")
      refute has_element?(view, "#user-password")
    end

    test "updates the name and lands on the user page", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})

      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace Hopper",
        email: "grace@example.com"
      })

      grant_capabilities!(["admin.user.update", "admin.user.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92/edit")

      view
      |> form("#user-form", user: %{name: "Grace M. Hopper", email: "grace@example.com"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path == "/users/92"

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
      assert has_element?(view, "h1", "Grace M. Hopper")
    end

    test "marks the account unverified when the email changes", %{conn: conn} do
      UserFixtures.insert_user!(%{id: 91, company_id: 73})

      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace Hopper",
        email: "grace@example.com",
        email_verified_at: ~N[2026-01-01 00:00:00]
      })

      grant_capabilities!(["admin.user.update", "admin.user.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92/edit")

      view
      |> form("#user-form", user: %{name: "Grace Hopper", email: "grace.hopper@example.com"})
      |> render_submit()

      {"/users/92", _flash} = assert_redirect(view)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
      assert has_element?(view, "#app-content", "unverified")
    end
  end
end
