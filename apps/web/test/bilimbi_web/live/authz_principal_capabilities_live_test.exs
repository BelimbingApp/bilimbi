defmodule BilimbiWeb.AuthzPrincipalCapabilitiesLiveTest do
  @moduledoc """
  Direct principal capabilities — the exceptions to the role model.

  Rows are created through `Authz.put_principal_capability/6`, so what is under
  test is what the platform actually stores.
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

  defp grant(scope, capability, allowed, opts \\ []) do
    type = Keyword.get(opts, :type, :user)
    id = Keyword.get(opts, :id, 91)
    {:ok, :stored} = Authz.put_principal_capability(scope, 73, type, id, capability, allowed)
  end

  defp open(conn) do
    grant_capabilities!("admin.authz.principal-capability.list")
    conn |> log_in_as() |> live(~p"/authz/principal-capabilities")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/principal-capabilities")
  end

  test "redirects away without admin.authz.principal-capability.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/principal-capabilities")
  end

  test "lists direct grants and marks its nav row current", %{conn: conn, scope: scope} do
    grant(scope, "admin.company.list", true)

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#principal-capabilities", "admin.company.list")
    assert has_element?(view, "#principal-capabilities", "Granted")
    assert has_element?(view, "#nav-admin-authz-principal-capability[aria-current='page']")
  end

  test "filters to denials, which outrank a role's grant", %{conn: conn, scope: scope} do
    grant(scope, "admin.company.list", true)
    grant(scope, "admin.company.view", false)

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "#principal-capabilities", "admin.company.list")

    view |> form("#grants-filters", %{"result" => "denied"}) |> render_change()

    assert has_element?(view, "#principal-capabilities", "admin.company.view")
    refute has_element?(view, "#principal-capabilities", "admin.company.list")
  end

  test "shows both user and employee principals, and can sort by type", %{
    conn: conn,
    scope: scope
  } do
    grant(scope, "admin.company.list", true, type: :user, id: 91)
    grant(scope, "admin.user.list", true, type: :agent, id: 7)

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#principal-capabilities", "Employee")
    assert has_element?(view, "#principal-capabilities", "User")

    # No principal-type filter: the administration query takes a principal
    # filter only as type *and* id together, so a type-only filter raises.
    # Sorting covers the same need without inventing an unsupported one.
    view |> element("#grants-sort-principal_type") |> render_click()
    assert %{"sort_by" => "principal_type"} = patched_params(view)
  end

  test "rejects a grant for a capability the registry does not know", %{scope: scope} do
    # I built an "Unknown" badge believing writes were unvalidated. They are
    # not: the API refuses the key outright. The badge stays, because a module
    # being uninstalled leaves rows whose capability the registry has
    # forgotten -- but that state cannot be produced through a public API, so
    # this pins the write-time behaviour instead of pretending otherwise.
    assert {:error, {:unknown_capabilities, ["typo.capability.list"]}} =
             Authz.put_principal_capability(scope, 73, :user, 91, "typo.capability.list", true)
  end

  test "search narrows by capability key", %{conn: conn, scope: scope} do
    grant(scope, "admin.company.list", true)
    grant(scope, "admin.user.list", true)

    {:ok, view, _html} = open(conn)

    view |> form("#grants-filters", %{"search" => "company"}) |> render_change()

    assert has_element?(view, "#principal-capabilities", "admin.company.list")
    refute has_element?(view, "#principal-capabilities", "admin.user.list")

    view |> form("#grants-filters", %{"search" => "zzz"}) |> render_change()
    assert render(view) =~ "No direct capabilities match these filters."
  end

  test "defaults to newest first and returns there when re-sorted", %{conn: conn, scope: scope} do
    grant(scope, "admin.company.list", true)

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#grants-sort-created_at .hero-chevron-down")

    view |> element("#grants-sort-capability") |> render_click()
    assert %{"sort_by" => "capability", "sort_dir" => "asc"} = patched_params(view)

    view |> element("#grants-sort-created_at") |> render_click()
    assert %{"sort_by" => "created_at", "sort_dir" => "desc"} = patched_params(view)
  end

  test "an unrecognised filter or sort in the URL falls back", %{conn: conn} do
    grant_capabilities!("admin.authz.principal-capability.list")

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/authz/principal-capabilities?sort_by=drop_table&result=maybe&page=x")

    assert has_element?(view, "#grants-search")
    assert has_element?(view, "#grants-result option[value=''][selected]")
  end

  test "renders the empty state for a viewer whose access comes from a role", %{
    conn: conn,
    scope: scope
  } do
    # The production path my earlier test missed. `grant_capabilities!/1`
    # grants the route capability *directly*, which puts a row on this very
    # page and hides the empty state. Reach the page through a role instead and
    # there is genuinely nothing to list -- which is where a stale reference to
    # a filter I had removed crashed with a KeyError.
    {:ok, role} = Authz.create_role(scope, 73, %{name: "Auditors", code: "auditors"})

    {:ok, _} =
      Authz.replace_role_capabilities(scope, role.id, ["admin.authz.principal-capability.list"])

    {:ok, :assigned} = Authz.assign_role(scope, 73, :user, 91, role.id)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/principal-capabilities")

    assert render(view) =~ "No capabilities have been granted directly"
  end

  test "a direct grant of the route capability lists itself", %{conn: conn} do
    # The other half: granted directly, the grant is a row here.
    {:ok, view, _html} = open(conn)

    assert has_element?(
             view,
             "#principal-capabilities",
             "admin.authz.principal-capability.list"
           )
  end

  test "a sort URL means what clicking that column means", %{conn: conn, scope: scope} do
    grant(scope, "admin.company.list", true)
    grant_capabilities!("admin.authz.principal-capability.list")

    # Same column, two routes to it: the link and the header. They must agree,
    # or a shared URL shows a different page than the click that produced it.
    {:ok, from_url, _html} =
      conn |> log_in_as() |> live(~p"/authz/principal-capabilities?sort_by=capability")

    assert has_element?(from_url, "#grants-sort-capability .hero-chevron-up")

    {:ok, from_click, _html} = open(conn)
    from_click |> element("#grants-sort-capability") |> render_click()
    assert %{"sort_dir" => "asc"} = patched_params(from_click)
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end
end
