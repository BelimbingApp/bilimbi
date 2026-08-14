defmodule BilimbiWeb.UserLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Bilimbi.Core.UserAdministration.Web.IndexLive

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

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 41,
      name: "Alpha Company",
      code: "alpha-company"
    })

    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      name: "Archived Company",
      code: "archived-company",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users")
  end

  test "redirects away when the actor lacks admin.user.list", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/users")
  end

  test "mounts the transferred adapter with the existing active menu", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    grant_capabilities!("admin.user.list")

    {:ok, %Phoenix.LiveViewTest.View{module: IndexLive} = view, _html} =
      conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#users-index")
    assert has_element?(view, "#users-search[placeholder='Search by name or email...']")
    assert has_element?(view, "#nav-admin-user[aria-current='page']")
  end

  test "lists only tenant-affiliated users and keeps archived company names read-only", %{
    conn: conn
  } do
    insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    insert_user!(%{id: 92, company_id: 76, name: "Archived User"})
    insert_user!(%{id: 93, company_id: nil, name: "Unassigned User"})
    insert_user!(%{id: 94, company_id: 74, name: "Foreign User"})

    grant_capabilities!([
      "admin.user.list",
      "admin.user.view",
      "admin.user.delete",
      "admin.company.view"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#user-91", "Ada Lovelace")
    assert has_element?(view, "#user-92", "Archived User")
    refute has_element?(view, "#user-93")
    refute has_element?(view, "#user-94")
    assert has_element?(view, "#user-91-company[href='/companies/73']", "Bilimbi Industries")
    refute has_element?(view, "#user-92-company")
    assert has_element?(view, "#user-92", "Archived Company")
    assert has_element?(view, "#user-92", "archived")
    assert has_element?(view, "#user-92-delete[disabled]")
  end

  test "gates create, view, update, and delete controls by existing capabilities", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})
    insert_user!(%{id: 92, company_id: 73, name: "Managed User"})
    grant_capabilities!("admin.user.list")

    {:ok, limited, _html} = conn |> log_in_as() |> live(~p"/users")

    refute has_element?(limited, "#user-new")
    refute has_element?(limited, "#user-92-show")
    refute has_element?(limited, "#user-92-edit")
    refute has_element?(limited, "#user-92-delete")

    grant_capabilities!([
      "admin.user.create",
      "admin.user.view",
      "admin.user.update",
      "admin.user.delete"
    ])

    {:ok, allowed, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(allowed, "#user-new[href='/users/new']")
    assert has_element?(allowed, "#user-92-show[href='/users/92']")
    assert has_element?(allowed, "#user-92-edit[href='/users/92/edit']")
    assert has_element?(allowed, "#user-92-delete:not([disabled])")
    assert has_element?(allowed, "#user-91-delete[disabled]")
  end

  test "preserves PostgreSQL LIKE contains, case, wildcard, and PHP-falsey search behavior", %{
    conn: conn
  } do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})
    insert_user!(%{id: 1, company_id: 73, name: "ALPHA", email: "one@example.com"})
    insert_user!(%{id: 2, company_id: 73, name: "Alpha", email: "two@example.com"})
    insert_user!(%{id: 3, company_id: 73, name: "Alpine", email: "target@EXAMPLE.com"})
    grant_capabilities!("admin.user.list")
    signed_in = log_in_as(conn)

    {:ok, name_view, _html} = live(signed_in, users_path(search: "LPH"))
    assert has_element?(name_view, "#user-1")
    refute has_element?(name_view, "#user-2")

    {:ok, email_view, _html} = live(signed_in, users_path(search: "target@"))
    assert has_element?(email_view, "#user-3")

    {:ok, underscore_view, _html} = live(signed_in, users_path(search: "A_pha"))
    assert has_element?(underscore_view, "#user-2")
    refute has_element?(underscore_view, "#user-1")

    for search <- ["%", "", "0"] do
      {:ok, view, _html} = live(signed_in, users_path(search: search))

      for id <- [1, 2, 3, 91] do
        assert has_element?(view, "#user-#{id}")
      end
    end
  end

  test "filters by multiple roles with OR semantics before bounded pagination", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})

    Enum.each(1..12, fn id ->
      insert_user!(%{
        id: id,
        company_id: 73,
        name: "Role User #{String.pad_leading(Integer.to_string(id), 2, "0")}",
        email: "role-user-#{id}@example.com"
      })
    end)

    {:ok, first} = Authz.create_role(scope!(), 73, %{name: "First", code: "first"})
    {:ok, second} = Authz.create_role(scope!(), 73, %{name: "Second", code: "second"})

    Enum.each(1..6, fn id ->
      assert {:ok, :assigned} = Authz.assign_role(scope!(), 73, :user, id, first.id)
    end)

    Enum.each(6..12, fn id ->
      assert {:ok, :assigned} = Authz.assign_role(scope!(), 73, :user, id, second.id)
    end)

    grant_capabilities!("admin.user.list")

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(users_path(roleIds: [first.id, second.id], perPage: 10))

    assert has_element?(view, "#users-role-filter option[value='#{first.id}']", "First")
    assert has_element?(view, "#users-role-filter option[value='#{second.id}']", "Second")
    assert has_element?(view, "#users-pagination-summary", "Showing 1–10 of 12")
    assert has_element?(view, "#user-6", "First")
    assert has_element?(view, "#user-6", "Second")
    assert has_element?(view, "#user-6")
  end

  test "dispatches every sort direction with descending id ties and Created descending first", %{
    conn: conn
  } do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})

    insert_user!(%{
      id: 1,
      company_id: 75,
      name: "Sort Same",
      email: "sort-z@example.com"
    })

    insert_user!(%{
      id: 2,
      company_id: 75,
      name: "Sort Same",
      email: "sort-a@example.com"
    })

    insert_user!(%{
      id: 3,
      company_id: 73,
      name: "Sort Other",
      email: "sort-m@example.com"
    })

    grant_capabilities!("admin.user.list")

    {:ok, view, _html} =
      conn |> log_in_as() |> live(users_path(search: "Sort", sortBy: "name", sortDir: "asc"))

    assert_row_order(view, [3, 2, 1])

    view |> element("#users-sort-name") |> render_click()
    assert_row_order(view, [2, 1, 3])

    view |> element("#users-sort-email") |> render_click()
    assert_row_order(view, [2, 3, 1])

    view |> element("#users-sort-email") |> render_click()
    assert_row_order(view, [1, 3, 2])

    view |> element("#users-sort-company") |> render_click()
    assert_row_order(view, [2, 1, 3])

    view |> element("#users-sort-company") |> render_click()
    assert_row_order(view, [3, 2, 1])

    view |> element("#users-sort-created") |> render_click()
    assert has_element?(view, "#users-sort-created .hero-chevron-down.text-action")
    assert_row_order(view, [3, 2, 1])

    view |> element("#users-sort-created") |> render_click()
    assert has_element?(view, "#users-sort-created .hero-chevron-up.text-action")
    assert_row_order(view, [3, 2, 1])
  end

  test "clamps page sizes and resets paging on filter, size, and sort changes", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})

    Enum.each(1..11, fn id ->
      insert_user!(%{
        id: id,
        company_id: 73,
        name: "Page User #{String.pad_leading(Integer.to_string(id), 2, "0")}",
        email: "page-user-#{id}@example.com"
      })
    end)

    grant_capabilities!("admin.user.list")
    signed_in = log_in_as(conn)

    {:ok, ten, _html} = live(signed_in, users_path(perPage: 1))
    assert has_element?(ten, "#users-page-size option[value='10'][selected]")
    assert has_element?(ten, "#users-pagination-summary", "Showing 1–10 of 12")

    {:ok, fifty, _html} = live(signed_in, users_path(perPage: 30))
    assert has_element?(fifty, "#users-page-size option[value='50'][selected]")
    assert has_element?(fifty, "#users-pagination-summary", "Showing 1–12 of 12")

    {:ok, hundred, _html} = live(signed_in, users_path(perPage: 9999))
    assert has_element?(hundred, "#users-page-size option[value='100'][selected]")

    {:ok, view, _html} = live(signed_in, users_path(page: 2, perPage: 10))
    assert has_element?(view, "#users-pagination-position", "Page 2 of 2")

    view
    |> form("#users-filters", filters: %{search: "Page", roleIds: [], perPage: "50"})
    |> render_change()

    assert has_element?(view, "#users-page-size option[value='50'][selected]")
    assert has_element?(view, "#users-pagination-position", "Page 1 of 1")

    {:ok, sort_view, _html} = live(signed_in, users_path(page: 2, perPage: 10))
    sort_view |> element("#users-sort-created") |> render_click()
    assert has_element?(sort_view, "#users-pagination-position", "Page 1 of 2")
    assert has_element?(sort_view, "#users-sort-created .hero-chevron-down.text-action")
  end

  test "renders truthful empty and out-of-range page states", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})
    grant_capabilities!("admin.user.list")
    signed_in = log_in_as(conn)

    {:ok, empty, _html} = live(signed_in, users_path(search: "no such account"))
    assert has_element?(empty, "#users-empty", "No users found")
    assert has_element?(empty, "#users-pagination-summary", "No results")
    assert has_element?(empty, "#users-pagination-position", "Page 0 of 0")

    {:ok, out_of_range, _html} = live(signed_in, users_path(page: 2, perPage: 10))
    assert has_element?(out_of_range, "#users-empty", "No users found")

    assert has_element?(
             out_of_range,
             "#users-pagination-summary",
             "No results on this page · 1 total"
           )

    assert has_element?(out_of_range, "#users-pagination-position", "Page 2 of 1")
  end

  test "hard deletes another user and refreshes the bounded page", %{conn: conn} do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})
    insert_user!(%{id: 92, company_id: 73, name: "Managed User"})
    grant_capabilities!(["admin.user.list", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")
    view |> element("#user-92-delete") |> render_click()

    assert has_element?(view, "#flash-group", "User deleted successfully")
    refute has_element?(view, "#user-92")
    assert {:error, :user_not_found} = User.get_tenant_user(scope!(), 92)
  end

  test "handles delete races, self deletion, missing capability, and archived companies", %{
    conn: conn
  } do
    insert_user!(%{id: 91, company_id: 73, name: "Signed In"})
    insert_user!(%{id: 92, company_id: 73, name: "Race User"})
    insert_user!(%{id: 93, company_id: 73, name: "Permission User"})
    insert_user!(%{id: 94, company_id: 76, name: "Archived User"})
    grant_capabilities!(["admin.user.list", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert :ok = User.delete_user(scope!(), 73, 92)
    view |> element("#user-92-delete") |> render_click()
    assert has_element?(view, "#flash-group", "no longer exists")
    refute has_element?(view, "#user-92")

    render_click(view, "delete", %{"id" => "91"})
    assert has_element?(view, "#flash-group", "cannot delete your own account")
    assert {:ok, _user} = User.get_tenant_user(scope!(), 91)

    render_click(view, "delete", %{"id" => "94"})
    assert has_element?(view, "#flash-group", "while their company is archived")
    assert {:ok, _user} = User.get_tenant_user(scope!(), 94)

    grant_capabilities!("admin.user.list", user_id: 93)

    {:ok, limited, _html} =
      conn
      |> log_in_as(%{"user_id" => 93, "company_id" => 73})
      |> live(~p"/users")

    render_click(limited, "delete", %{"id" => "91"})
    assert has_element?(limited, "#flash-group", "do not have permission")
    assert {:ok, _user} = User.get_tenant_user(scope!(), 91)
  end

  defp insert_user!(attributes) do
    id = Map.fetch!(attributes, :id)

    attributes
    |> Map.put_new(:password_hash, "not-used")
    |> Map.put_new(:email, "user-#{id}@example.com")
    |> UserFixtures.insert_user!()
  end

  defp scope! do
    {:ok, scope} = Tenancy.scope(41)
    scope
  end

  defp users_path(params), do: ~p"/users?#{Map.new(params)}"

  defp assert_row_order(view, ids) do
    ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, position} ->
      assert has_element?(view, "#users > tr:nth-child(#{position})#user-#{id}")
    end)
  end
end
