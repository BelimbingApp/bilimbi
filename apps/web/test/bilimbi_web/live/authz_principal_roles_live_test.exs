defmodule BilimbiWeb.AuthzPrincipalRolesLiveTest do
  @moduledoc """
  Tenant-wide principal-role assignments.

  Rows are created through `Authz.assign_role/5`. Principal names stay ids
  until #285; company names come from the directory seam.
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
             "Page 1 of 1 · 1 assignment"
           )

    refute has_element?(view, "#assignments-prev")
    refute has_element?(view, "#assignments-next")
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
