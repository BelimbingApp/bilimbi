defmodule BilimbiWeb.AuthzPrincipalRolesLiveTest do
  @moduledoc """
  Tenant-wide principal-role assignments.

  Rows are created through `Authz.assign_role/5`. Principal and company names
  both come from directory seams — `PrincipalDirectory` (#441) and
  `CompanyDirectory` (#183) — so neither is a join into Core.
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
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  defp assign_listed_role!(scope, attrs, opts \\ []) do
    company_id = Keyword.get(opts, :company_id, 73)
    type = Keyword.get(opts, :type, :user)
    id = Keyword.get(opts, :id, 91)
    {:ok, role} = Authz.create_role(scope, company_id, attrs)
    {:ok, :assigned} = Authz.assign_role(scope, company_id, type, id, role.id)
    role
  end

  defp open(conn) do
    grant_capabilities!("admin.authz.principal-role.list")
    conn |> log_in_as() |> live(~p"/authz/principal-roles")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/principal-roles")
  end

  test "redirects away without admin.authz.principal-role.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/principal-roles")
  end

  test "lists assignments, names the company, and marks its nav row current", %{
    conn: conn,
    scope: scope
  } do
    assign_listed_role!(scope, %{name: "Local viewer", code: "local_viewer"})

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#principal-roles", "Local viewer")
    assert has_element?(view, "#principal-roles", "Bilimbi Industries")
    assert has_element?(view, "#principal-roles", "User")
    assert has_element?(view, "#nav-admin-authz-principal-role[aria-current='page']")
  end

  test "shows the count without dead page controls on a single page", %{conn: conn, scope: scope} do
    assign_listed_role!(scope, %{name: "Local viewer", code: "local_viewer"})
    {:ok, view, _html} = open(conn)

    assert has_element?(
             view,
             "#assignments-pagination-summary",
             "Showing 1 to 1 of 1 results"
           )

    assert has_element?(view, "#assignments-pagination-page-size")
    refute has_element?(view, "#assignments-pagination-previous")
    refute has_element?(view, "#assignments-pagination-next")
  end

  test "search narrows by role name", %{conn: conn, scope: scope} do
    assign_listed_role!(scope, %{name: "Local viewer", code: "local_viewer"})
    assign_listed_role!(scope, %{name: "Local editor", code: "local_editor"})

    {:ok, view, _html} = open(conn)

    view |> form("#assignments-filters", %{"search" => "editor"}) |> render_change()

    assert has_element?(view, "#principal-roles", "Local editor")
    refute has_element?(view, "#principal-roles", "Local viewer")

    view |> form("#assignments-filters", %{"search" => "zzz"}) |> render_change()

    assert has_element?(
             view,
             "#principal-roles-empty",
             "No principal role assignments match these filters"
           )
  end

  test "defaults to newest first and sorts role name ascending on first click", %{
    conn: conn,
    scope: scope
  } do
    assign_listed_role!(scope, %{name: "Local viewer", code: "local_viewer"})

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#assignments-sort-created_at .hero-chevron-down")

    view |> element("#assignments-sort-role_name") |> render_click()
    assert %{"sort_by" => "role_name", "sort_dir" => "asc"} = patched_params(view)
  end

  test "sorts the company column by display name, not company id", %{conn: conn, scope: scope} do
    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Aurora Works",
      code: "aurora_works"
    })

    assign_listed_role!(scope, %{name: "Industries role", code: "industries_role"},
      company_id: 73
    )

    assign_listed_role!(scope, %{name: "Aurora role", code: "aurora_role"}, company_id: 74)

    grant_capabilities!("admin.authz.principal-role.list")

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/authz/principal-roles?sort_by=company_name")

    assert has_element?(view, "#principal-roles > tr:nth-child(1)", "Aurora Works")
    assert has_element?(view, "#principal-roles > tr:nth-child(2)", "Bilimbi Industries")
  end

  test "names a principal inside the tenant and keeps the id outside it", %{
    conn: conn,
    scope: scope
  } do
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other Tenant"})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Other Company",
      code: "other_company"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    assign_listed_role!(scope, %{name: "Local auditor", code: "local_auditor"}, id: 91)
    assign_listed_role!(scope, %{name: "Foreign auditor", code: "foreign_auditor"}, id: 92)

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#principal-roles td", "Ada Lovelace")
    assert has_element?(view, "#principal-roles td", "92")
    refute has_element?(view, "#principal-roles td", "Grace Hopper")
  end

  test "sorts the principal column by name, not by principal id", %{conn: conn, scope: scope} do
    UserFixtures.insert_user!(%{
      id: 12,
      company_id: 73,
      name: "Zoe Quinn",
      email: "zoe@example.com"
    })

    assign_listed_role!(scope, %{name: "Alpha role", code: "alpha_role"}, id: 12)
    assign_listed_role!(scope, %{name: "Beta role", code: "beta_role"}, id: 91)

    grant_capabilities!("admin.authz.principal-role.list")

    # Zoe holds the lower id and the later name, so id order and name order
    # disagree and only one of them can produce this sequence.
    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/authz/principal-roles?sort_by=principal_name&sort_dir=asc")

    assert has_element?(view, "#principal-roles > tr:nth-child(1)", "Ada Lovelace")
    assert has_element?(view, "#principal-roles > tr:nth-child(2)", "Zoe Quinn")

    view |> element("#assignments-sort-principal_name") |> render_click()
    assert %{"sort_by" => "principal_name"} = patched_params(view)
  end

  test "search finds an assignment by the principal's name", %{conn: conn, scope: scope} do
    assign_listed_role!(scope, %{name: "Local auditor", code: "local_auditor"}, id: 91)

    {:ok, view, _html} = open(conn)

    # "Lovelace" is in no column of this table; it is only the name the
    # directory resolves for user 91.
    view |> form("#assignments-filters", %{"search" => "Lovelace"}) |> render_change()

    assert has_element?(view, "#principal-roles td", "Ada Lovelace")
    assert has_element?(view, "#principal-roles td", "Local auditor")
  end

  test "an unrecognised sort in the URL falls back", %{conn: conn, scope: scope} do
    assign_listed_role!(scope, %{name: "Local viewer", code: "local_viewer"})
    grant_capabilities!("admin.authz.principal-role.list")

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/authz/principal-roles?sort_by=drop_table&page=x")

    assert has_element?(view, "#assignments-search")
    assert has_element?(view, "#assignments-sort-created_at .hero-chevron-down")
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end
end
