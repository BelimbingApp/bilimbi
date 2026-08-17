defmodule BilimbiWeb.AuthzRolesLiveTest do
  @moduledoc """
  Roles list and detail.

  The assertion that matters most here is the tenancy boundary. `Authz` owns
  the rule; these prove the screens inherit it rather than quietly widening
  it, because a leak would look like a perfectly ordinary list.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy
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

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    {:ok, ours} = Tenancy.scope(41)
    {:ok, theirs} = Tenancy.scope(42)
    %{ours: ours, theirs: theirs}
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  defp open_index(conn) do
    grant_capabilities!("admin.authz.role.list")
    conn |> log_in_as() |> live(~p"/authz/roles")
  end

  describe "index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/roles")
    end

    test "redirects away without admin.authz.role.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles")
    end

    test "offers Create Role only to an actor holding the capability", %{conn: conn} do
      # Belimbing gates this action the same way (`index.blade.php:6-12`,
      # `@if ($canCreate)`). Without it the create screen is reachable only by
      # typing the URL, which is how it shipped in #221.
      grant_capabilities!(["admin.authz.role.list", "admin.authz.role.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles")

      # Asserted as an anchor, not just by id. `<.button>` renders a `<button>`
      # unless it is given navigate/href/patch, so wrapping it in a `<.link>`
      # produces `<a><button>` -- invalid, and the element that takes the click
      # is not the one that navigates. An id-only assertion passes either way.
      assert has_element?(view, "a#roles-create[href='/authz/roles/create']")
      refute has_element?(view, "#roles-create button")
    end

    test "hides Create Role from an actor who cannot create", %{conn: conn} do
      {:ok, view, _html} = open_index(conn)

      refute has_element?(view, "#roles-create")
    end

    test "lists roles and marks its own nav row current", %{conn: conn, ours: ours} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_index(conn)

      assert has_element?(view, "#roles", "Auditor")
      assert has_element?(view, "#nav-admin-authz-role[aria-current='page']")
    end

    test "does not show another tenant's custom role", %{conn: conn, ours: ours, theirs: theirs} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Ours", code: "ours"})
      {:ok, _} = Authz.create_role(theirs, 74, %{name: "Theirs", code: "theirs"})

      {:ok, view, _html} = open_index(conn)

      # The rule lives in Authz.list_roles/2, not the LiveView. This asserts the
      # screen inherits it -- a leak here reads as an ordinary extra row.
      assert has_element?(view, "#roles", "Ours")
      refute has_element?(view, "#roles", "Theirs")
    end

    test "filters by search and reports an empty result against the term", %{
      conn: conn,
      ours: ours
    } do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Bookkeeper", code: "bookkeeper"})

      {:ok, view, _html} = open_index(conn)

      view |> form("#roles-filters", %{"search" => "Book"}) |> render_change()

      assert has_element?(view, "#roles", "Bookkeeper")
      refute has_element?(view, "#roles", "Auditor")

      view |> form("#roles-filters", %{"search" => "zzz"}) |> render_change()
      assert render(view) =~ "No roles match zzz"
    end

    test "sorting toggles direction and survives in the URL", %{conn: conn, ours: ours} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_index(conn)

      # Assert the params, not their serialisation order -- the encoder is free
      # to reorder a map and this test should not fail when it does.
      view |> element("#roles-sort-code") |> render_click()
      assert %{"sort_by" => "code", "sort_dir" => "asc"} = patched_params(view)

      view |> element("#roles-sort-code") |> render_click()
      assert %{"sort_by" => "code", "sort_dir" => "desc"} = patched_params(view)
    end

    test "a hand-edited sort column falls back instead of crashing", %{conn: conn} do
      grant_capabilities!("admin.authz.role.list")

      # String.to_existing_atom on unvalidated input is the classic way this
      # page would 500 on a URL somebody typed.
      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/authz/roles?sort_by=drop_table&page=notanumber")

      assert has_element?(view, "#roles-search")
    end
  end

  describe "show" do
    test "redirects away without admin.authz.role.view", %{conn: conn, ours: ours} do
      {:ok, role} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")
    end

    test "shows capabilities and principals", %{conn: conn, ours: ours} do
      {:ok, role} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})
      grant_capabilities!(["admin.authz.role.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")

      assert has_element?(view, "h1", "Auditor")
      assert has_element?(view, "#role-summary", "Custom")
      assert has_element?(view, "#role-principals")
      assert has_element?(view, "#role-principals-empty", "Nobody in this tenant holds this role")
    end

    test "labels a principal by what it means, not the stored word", %{conn: conn, ours: ours} do
      {:ok, role} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})
      {:ok, :assigned} = Authz.assign_role(ours, 73, :agent, 7, role.id)
      grant_capabilities!(["admin.authz.role.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")

      # principal_type is a :string column. Matching atoms fell through
      # silently and rendered the raw "agent"; nothing but an assertion on the
      # label itself would notice.
      assert has_element?(view, "#role-principals", "Employee")
      refute has_element?(view, "#role-principals", "agent")
    end

    test "another tenant's role is not found rather than forbidden", %{
      conn: conn,
      theirs: theirs
    } do
      {:ok, role} = Authz.create_role(theirs, 74, %{name: "Theirs", code: "theirs"})
      grant_capabilities!(["admin.authz.role.view", "admin.authz.role.list"])

      # Distinguishing "forbidden" from "missing" would confirm the role exists.
      assert {:error, {:live_redirect, %{to: "/authz/roles"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")
    end

    test "a non-numeric id redirects instead of raising", %{conn: conn} do
      grant_capabilities!(["admin.authz.role.view", "admin.authz.role.list"])

      assert {:error, {:live_redirect, %{to: "/authz/roles"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/not-an-id")
    end
  end

  describe "create" do
    defp open_create(conn) do
      grant_capabilities!("admin.authz.role.create")
      conn |> log_in_as() |> live(~p"/authz/roles/create")
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/roles/create")
    end

    test "redirects away without admin.authz.role.create", %{conn: conn} do
      grant_capabilities!("admin.authz.role.list")

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/create")
    end

    test "the literal path wins over /authz/roles/:id", %{conn: conn} do
      # Declared before the parameterised route. If that order is ever lost,
      # RoleShowLive matches "create" as an id and redirects instead, so this
      # asserts the form renders rather than merely that the request succeeds.
      {:ok, view, _html} = open_create(conn)

      assert has_element?(view, "#role-form")
    end

    test "creates a company-owned role and returns to the index", %{conn: conn, ours: ours} do
      {:ok, view, _html} = open_create(conn)

      assert {:error, {:live_redirect, %{to: "/authz/roles"}}} =
               view
               |> form("#role-form", %{
                 "role" => %{
                   "name" => "Billing Manager",
                   "code" => "billing_manager",
                   "description" => "Handles invoices"
                 }
               })
               |> render_submit()

      created = ours |> Authz.list_roles() |> Enum.find(&(&1.code == "billing_manager"))

      assert created.name == "Billing Manager"
      # create_role/3 forces both, so a system role can never be built here.
      refute created.is_system
      assert created.company_id == 73
    end

    test "rejects a code the database format constraint would refuse", %{conn: conn} do
      {:ok, view, _html} = open_create(conn)

      html =
        view
        |> form("#role-form", %{"role" => %{"name" => "Bad", "code" => "Billing Manager"}})
        |> render_submit()

      assert html =~ "lowercase letters, digits and underscores"
      assert has_element?(view, "#role-form")
    end

    test "surfaces a duplicate code on the field the user can edit", %{conn: conn, ours: ours} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_create(conn)

      # Uniqueness is the database's to enforce -- the form cannot know it
      # without racing -- so the domain changeset error has to land back on
      # :code rather than surfacing as a crash or a bare flash.
      html =
        view
        |> form("#role-form", %{"role" => %{"name" => "Auditor Again", "code" => "auditor"}})
        |> render_submit()

      assert html =~ "has already been taken"
      assert has_element?(view, "#role-form")
    end
  end
end
