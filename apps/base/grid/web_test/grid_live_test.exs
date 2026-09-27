defmodule Bilimbi.Base.Grid.Web.GridLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @all ~w(admin.user.list admin.company.list admin.employee.list admin.employee-type.list)

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_departments_table!()
    CompanyFixtures.create_department_types_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Bilimbi Industries"})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Retail",
      code: "bilimbi_retail",
      parent_id: 73
    })

    CompanyFixtures.assign_primary_company!(41, 73)

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 93,
      company_id: 73,
      name: "Linus Pauling",
      email: "linus@example.com"
    })

    :ok
  end

  test "the page needs a signed-in account", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/grid")
  end

  test "the index lists only the tables the account may read", %{conn: conn} do
    grant_capabilities!(~w(admin.company.list))
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid")

    assert has_element?(view, "#grid-table-companies", "Companies")
    assert has_element?(view, "#grid-table-departments")
    refute has_element?(view, "#grid-table-users")
  end

  test "a table outside the catalog sends the account back to the index", %{conn: conn} do
    grant_capabilities!(~w(admin.company.list))
    conn = log_in_as(conn)

    assert {:error, {:live_redirect, %{to: "/grid", flash: flash}}} = live(conn, ~p"/grid/users")
    assert flash["error"] =~ "not in your catalog"
  end

  test "a table opens with its own fields and rows in the full mode", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users")

    assert has_element?(view, "#grid-chip-name", "Name")
    assert has_element?(view, "#grid-chip-email", "Email")
    assert has_element?(view, "#grid-head-created_at")
    assert has_element?(view, "#grid-row-91")
    assert has_element?(view, "#grid-cell-91-email", "ada@example.com")
    assert has_element?(view, "#grid-pagination-summary", "Showing 1 to 3 of 3 results")
    assert has_element?(view, "#grid-zoom-full[aria-pressed='true']")
    refute has_element?(view, "#grid-canvas")
  end

  test "typing in the add bar suggests walked columns, and picking one adds it to the URL", %{
    conn: conn
  } do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users")

    view |> form("#grid-add-column", %{add: "company name"}) |> render_change()
    assert has_element?(view, "#grid-suggest-company-name", "Company › Name")
    assert has_element?(view, "#grid-suggest-company-parent-name")

    view |> element("#grid-suggest-company-name") |> render_click()

    assert_patch(
      view,
      ~p"/grid/users?cols=id%2Cname%2Cemail%2Cemail_verified_at%2Ccreated_at%2Cupdated_at%2Ccompany.name"
    )

    assert has_element?(view, "#grid-chip-company-name", "Company name")
    assert has_element?(view, "#grid-head-company-name[title='Company › Name']")
    assert has_element?(view, "#grid-cell-91-company-name", "Bilimbi Industries")
    assert has_element?(view, "#grid-cell-92-company-name", "Bilimbi Retail")
    refute has_element?(view, "#grid-suggestions")
  end

  test "a typed spec adds on Enter, and a spec outside the catalog is left out with a message", %{
    conn: conn
  } do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")

    view
    |> form("#grid-add-column", %{add: "company.parent.name"})
    |> render_submit(%{"op" => "add_typed"})

    assert_patch(view, ~p"/grid/users?cols=name%2Ccompany.parent.name")
    assert has_element?(view, "#grid-cell-92-company-parent-name", "Bilimbi Industries")

    {:ok, view, html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cnope.here")
    assert html =~ "Left out: nope.here"
    assert has_element?(view, "#grid-chip-name")
    refute has_element?(view, "#grid-chip-nope-here")
  end

  test "columns are removed and reordered, and the URL follows", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cemail%2Ccompany.name")

    view |> element("#grid-remove-email") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name%2Ccompany.name")
    refute has_element?(view, "#grid-chip-email")

    render_hook(view, "grid", %{"op" => "move", "spec" => "company.name", "before" => "name"})
    assert_patch(view, ~p"/grid/users?cols=company.name%2Cname")
  end

  test "a rollup column counts, sorts, and expands in place", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Ccompany.users%3Acount")

    assert has_element?(view, "#grid-cell-91-company-users_count", "2")
    assert has_element?(view, "#grid-cell-92-company-users_count", "1")

    view |> element("#grid-sort-company-users_count") |> render_click()

    assert_patch(
      view,
      ~p"/grid/users?cols=name%2Ccompany.users%3Acount&sort=company.users%3Acount"
    )

    assert has_element?(view, "#grid-head-company-users_count[aria-sort='ascending']")

    view |> element("#grid-expand-91-company-users_count") |> render_click()
    assert has_element?(view, "#grid-row-91-company-users_count", "ada@example.com")
    assert has_element?(view, "#grid-row-91-company-users_count", "linus@example.com")
    assert has_element?(view, "#grid-expand-91-company-users_count[aria-expanded='true']")

    view |> element("#grid-expand-91-company-users_count") |> render_click()
    refute has_element?(view, "#grid-row-91-company-users_count")
  end

  test "a lens paints bands into the cells and lives in the URL", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/companies?cols=name%2Cusers%3Acount")

    view |> element("#grid-lens-users_count-band") |> render_click()
    assert_patch(view, ~p"/grid/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cband")

    assert has_element?(
             view,
             "#grid-cell-73-users_count[data-scale='sequential'][data-band='4']",
             "2"
           )

    assert has_element?(view, "#grid-cell-74-users_count[data-band='0']", "1")

    view |> element("#grid-lens-users_count-bar") |> render_click()
    assert_patch(view, ~p"/grid/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cbar")
    assert has_element?(view, "#grid-cell-73-users_count [data-bar='100']")
  end

  test "zooming out switches to the canvas, and windows are served on request", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cemail")

    view |> element("#grid-zoom-carpet") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name%2Cemail&z=3")
    assert has_element?(view, "#grid-canvas")
    assert has_element?(view, "#grid-zoom-carpet[aria-pressed='true']")
    assert has_element?(view, "#grid-window-summary", "3 rows by 2 columns")
    refute has_element?(view, "#grid-pagination")

    render_hook(view, "grid", %{
      "op" => "window",
      "offset" => 0,
      "limit" => 50,
      "detail" => "levels"
    })

    assert_push_event(view, "grid:window", %{offset: 0, total: 3, rows: rows})
    assert [[91, [[nil, _n, _band, :categorical, nil], _email]], [92, _], [93, _]] = rows

    assert render_hook(view, "grid", %{"op" => "cell", "row" => 1, "col" => "email"}) =~
             "grid-canvas"

    view |> element("#grid-zoom-in") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name%2Cemail&z=4")
  end

  test "a dragged rectangle zooms to fit it, back to the table when it is small", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cemail&z=3")

    render_hook(view, "grid", %{
      "op" => "zoom_rect",
      "from_row" => 0,
      "to_row" => 3,
      "from_col" => 0,
      "to_col" => 2,
      "width" => 1200,
      "height" => 600
    })

    assert_patch(view, ~p"/grid/users?cols=name%2Cemail&z=40")
    refute has_element?(view, "#grid-canvas")
  end

  test "search, page size and grouping keep to the URL", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")

    view |> form("#grid-filters", %{filters: %{search: "grace"}}) |> render_change()
    assert_patch(view, ~p"/grid/users?cols=name&q=grace")
    assert has_element?(view, "#grid-row-92")
    refute has_element?(view, "#grid-row-91")

    view |> form("#grid-filters", %{filters: %{search: "nobody here"}}) |> render_change()
    assert_patch(view, ~p"/grid/users?cols=name&q=nobody+here")
    assert has_element?(view, "#grid-empty", "No rows match")

    view |> element("#grid-clear-search") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name")

    render_hook(view, "grid", %{"op" => "group", "spec" => "name"})
    path = assert_patch(view)

    assert URI.decode_query(URI.parse(path).query) == %{
             "cols" => "name",
             "sort" => "name",
             "group" => "name"
           }

    assert has_element?(view, "#grid-grouped", "Grouped by name")
  end

  test "grouping by a column sorts by it and heads each run of equal values", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/grid/users?cols=name%2Ccompany.name&group=company.name&sort=company.name")

    assert has_element?(view, "#grid-group-0 th", "Company name: Bilimbi Industries")
    assert has_element?(view, "#grid-group-0 th", "(2)")
    assert has_element?(view, "#grid-group-1 th", "Company name: Bilimbi Retail")
    assert has_element?(view, "#grid-grouped", "Grouped by company.name")

    view |> element("#grid-ungroup") |> render_click()
    path = assert_patch(view)
    refute Map.has_key?(URI.decode_query(URI.parse(path).query), "group")
    refute has_element?(view, "#grid-group-0")
  end

  test "a view is saved under a name, reopened by its slug, and deleted through the confirmation",
       %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/grid/users?cols=name%2Ccompany.name&z=32&sort=name&dir=desc")

    assert has_element?(view, "#grid-views-empty")

    view |> element("#grid-save-view") |> render_click()
    assert has_element?(view, "#grid-save-dialog")
    view |> form("#grid-save-form", %{view: %{label: "Ops desk"}}) |> render_submit()
    assert_patch(view, ~p"/grid/users?v=ops-desk")
    assert render(view) =~ "View “Ops desk” saved."

    assert has_element?(view, "#grid-view-own-ops-desk", "Ops desk")
    assert has_element?(view, "#grid-chip-company-name")
    assert has_element?(view, "#grid-zoom-full[aria-pressed='true']")
    assert has_element?(view, "#grid-zoom-level", "32 px")
    assert has_element?(view, "#grid-head-name[aria-sort='descending']")

    # A gesture on a saved view is an unsaved change: the URL spells it out and drops the name.
    view |> element("#grid-remove-company-name") |> render_click()
    path = assert_patch(view)

    assert URI.decode_query(URI.parse(path).query) == %{
             "cols" => "name",
             "z" => "32",
             "sort" => "name",
             "dir" => "desc"
           }

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?v=ops-desk")
    assert has_element?(view, "#grid-chip-company-name")

    assert has_element?(
             view,
             "#grid-view-own-ops-desk-tile[href='/workspace?t=%2Fgrid%2Fusers%3Fv%3Dops-desk']"
           )

    view |> element("#grid-view-own-ops-desk-delete") |> render_click()
    assert has_element?(view, "#grid-delete-view-confirm")
    view |> element("#grid-delete-view-confirm button", "Delete") |> render_click()
    assert render(view) =~ "View “Ops desk” deleted."
    path = assert_patch(view)

    assert URI.decode_query(URI.parse(path).query) == %{
             "cols" => "name,company.name",
             "z" => "32",
             "sort" => "name",
             "dir" => "desc"
           }

    assert has_element?(view, "#grid-views-empty")

    {:ok, view, html} = conn |> log_in_as() |> live(~p"/grid/users?v=ops-desk")
    assert html =~ "That saved view no longer exists."
    assert has_element?(view, "#grid-chip-name")
  end

  test "a shared view needs the company settings capability and is seen by another account", %{
    conn: conn
  } do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")

    view |> element("#grid-save-view") |> render_click()
    refute has_element?(view, "#grid-save-shared")
    # The checkbox is withheld, so the flag can only arrive by hand; the handler refuses it.
    view
    |> form("#grid-save-form", %{view: %{label: "Team"}})
    |> render_submit(%{"view" => %{"shared" => "true"}})

    assert render(view) =~ "You do not have permission to share views with the company."

    grant_capabilities!(~w(base.settings.company.manage))
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")
    view |> element("#grid-save-view") |> render_click()
    assert has_element?(view, "#grid-save-shared")
    view |> form("#grid-save-form", %{view: %{label: "Team", shared: "true"}}) |> render_submit()
    assert_patch(view, ~p"/grid/users?v=shared%3Ateam")
    assert has_element?(view, "#grid-view-shared-team", "shared")

    grant_capabilities!(@all, user_id: 92, company_id: 74)

    {:ok, other, _html} =
      conn |> log_in_as(%{"user_id" => 92, "company_id" => 74}) |> live(~p"/grid/users")

    refute has_element?(other, "#grid-view-shared-team")

    grant_capabilities!(@all, user_id: 93)

    {:ok, colleague, _html} =
      conn
      |> log_in_as(%{"user_id" => 93, "company_id" => 73})
      |> live(~p"/grid/users?v=shared%3Ateam")

    assert has_element?(colleague, "#grid-view-shared-team")
    assert has_element?(colleague, "#grid-chip-name")
    refute has_element?(colleague, "#grid-chip-email")
    refute has_element?(colleague, "#grid-view-shared-team-delete")
  end

  defp framed(conn), do: put_req_header(conn, "sec-fetch-dest", "iframe")

  test "in a workspace the grid follows a selection and narrows to the record it names", %{
    conn: conn
  } do
    grant_capabilities!(@all)
    token = Bilimbi.Base.UI.Workspace.host_token("phx-a-host")
    topic = Bilimbi.Base.UI.Workspace.topic(41, 91, token)
    :ok = Bilimbi.Base.UI.Workspace.subscribe(topic)

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> framed()
      |> live(~p"/grid/users?cols=name%2Ccompany.name&ws=#{token}")

    assert_receive {:workspace_joined}
    assert has_element?(view, "#grid-follow-select option[value='self']")
    assert has_element?(view, "#grid-follow-select option[value='company']")
    refute has_element?(view, "#grid-follow-waiting")
    assert has_element?(view, "#grid-row-91")
    assert has_element?(view, "#grid-row-92")

    # Choosing to follow the selected company tells the host the kind.
    view |> form("#grid-follow-form", %{follow: %{follow: "company"}}) |> render_change()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["follow"] == "company"
    assert_receive {:workspace_page_follows, pid, ["core/company"]}
    assert pid == view.pid
    assert has_element?(view, "#grid-follow-waiting")

    # A fact of that kind narrows the rows; one of another kind is ignored.
    :ok =
      Bilimbi.Base.UI.Workspace.broadcast(topic, {:workspace_fact, %{kind: "core/user", id: 92}})

    :ok =
      Bilimbi.Base.UI.Workspace.broadcast(
        topic,
        {:workspace_fact, %{kind: "core/company", id: 74}}
      )

    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["focus"] == "74"
    assert has_element?(view, "#grid-focus", "74")
    assert has_element?(view, "#grid-row-92")
    refute has_element?(view, "#grid-row-91")

    # The way back keeps the follow and drops the record.
    view |> element("#grid-unfocus") |> render_click()
    path = assert_patch(view)
    query = URI.decode_query(URI.parse(path).query)
    assert query["follow"] == "company" and not Map.has_key?(query, "focus")
    assert has_element?(view, "#grid-row-91")

    # Following the grid's own records narrows to that row.
    view |> form("#grid-follow-form", %{follow: %{follow: "self"}}) |> render_change()
    assert_patch(view)
    assert_receive {:workspace_page_follows, _pid, ["core/user"]}

    :ok =
      Bilimbi.Base.UI.Workspace.broadcast(topic, {:workspace_fact, %{kind: "core/user", id: 93}})

    assert_patch(view)
    assert has_element?(view, "#grid-row-93")
    refute has_element?(view, "#grid-row-91")

    # A key that does not read as one is no selection.
    :ok =
      Bilimbi.Base.UI.Workspace.broadcast(
        topic,
        {:workspace_fact, %{kind: "core/user", id: "abc"}}
      )

    assert_patch(view)
    assert has_element?(view, "#grid-follow-waiting")
    assert has_element?(view, "#grid-row-91")
  end

  test "outside a workspace a focus in the address still narrows, with the way back, and nothing to follow",
       %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/users?cols=name&follow=company&focus=74")

    refute has_element?(view, "#grid-follow-select")
    refute has_element?(view, "#grid-follow-waiting")
    assert has_element?(view, "#grid-focus", "74")
    assert has_element?(view, "#grid-row-92")
    refute has_element?(view, "#grid-row-91")

    view |> element("#grid-unfocus") |> render_click()
    assert_patch(view)
    refute has_element?(view, "#grid-follow")
    assert has_element?(view, "#grid-row-91")
  end

  test "a shared view limited to a role opens only for people assigned that role in the company",
       %{conn: conn} do
    grant_capabilities!(@all ++ ~w(base.settings.company.manage))
    {:ok, tenant_scope} = Tenancy.scope(41)

    {:ok, role} =
      Bilimbi.Base.Authz.create_role(tenant_scope, 73, %{name: "Reviewer", code: "reviewer"})

    {:ok, :assigned} = Bilimbi.Base.Authz.assign_role(tenant_scope, 73, :user, 91, role.id)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")
    view |> element("#grid-save-view") |> render_click()
    assert has_element?(view, "#grid-save-roles")

    view
    |> form("#grid-save-form", %{view: %{label: "Review desk", shared: "true"}})
    |> render_submit(%{"view" => %{"roles" => ["reviewer"]}})

    assert_patch(view, ~p"/grid/users?v=shared%3Areview-desk")
    assert has_element?(view, "#grid-view-shared-review-desk", "shared: reviewer")

    # A colleague without the role sees neither the entry nor the address.
    UserFixtures.insert_user!(%{id: 96, company_id: 73, name: "Peer", email: "peer@example.com"})
    grant_capabilities!(@all, user_id: 96)
    peer_conn = log_in_as(conn, %{"user_id" => 96, "company_id" => 73})
    {:ok, peer, _html} = live(peer_conn, ~p"/grid/users")
    refute has_element?(peer, "#grid-view-shared-review-desk")
    {:ok, _peer, html} = live(peer_conn, ~p"/grid/users?v=shared%3Areview-desk")
    assert html =~ "That saved view no longer exists."

    # A colleague with the role opens it.
    {:ok, :assigned} = Bilimbi.Base.Authz.assign_role(tenant_scope, 73, :user, 96, role.id)
    {:ok, peer, _html} = live(peer_conn, ~p"/grid/users?v=shared%3Areview-desk")
    assert has_element?(peer, "#grid-view-shared-review-desk")
    assert has_element?(peer, "#grid-chip-name")
    refute has_element?(peer, "#grid-chip-email")

    # A role code outside the company is refused.
    view |> element("#grid-save-view") |> render_click()

    view
    |> form("#grid-save-form", %{view: %{label: "Other", shared: "true"}})
    |> render_submit(%{"view" => %{"roles" => ["not_here"]}})

    assert render(view) =~ "Choose role codes from this company."
  end

  test "a rollup over dated rows offers the trend and the change since a date", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/companies?cols=name%2Cusers%3Acount")

    assert has_element?(view, "#grid-lens-users_count-trend")
    assert has_element?(view, "#grid-lens-users_count-delta")
    refute has_element?(view, "#grid-since")

    view |> element("#grid-lens-users_count-trend") |> render_click()
    assert_patch(view, ~p"/grid/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Ctrend")
    assert has_element?(view, "#grid-cell-73-users_count polyline[points]")
    assert has_element?(view, "#grid-cell-73-users_count", "2")

    # The fixture dates no user, and an undated row never counts as already
    # there: date them in January so the change since a date can be read.
    Bilimbi.Base.Repo.query!("UPDATE users SET created_at = $1", [~N[2026-01-15 09:00:00]])

    view |> element("#grid-lens-users_count-delta") |> render_click()
    assert_patch(view, ~p"/grid/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cdelta")
    assert has_element?(view, "#grid-since")
    # Thirty days ago every user already existed: no change since then.
    assert has_element?(view, "#grid-cell-73-users_count", "2 (±0)")
    assert has_element?(view, "#grid-cell-74-users_count", "1 (±0)")

    # Since the start of the year, every user is new.
    view |> form("#grid-filters", %{filters: %{since: "2026-01-01"}}) |> render_change()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["since"] == "2026-01-01"
    assert has_element?(view, "#grid-cell-73-users_count", "2 (+2)")
    assert has_element?(view, "#grid-cell-74-users_count", "1 (+1)")

    # The carpet window carries the series for the compact sparkline.
    view |> element("#grid-zoom-mid") |> render_click()
    assert_patch(view)
    view |> element("#grid-lens-users_count-trend") |> render_click()
    assert_patch(view)

    render_hook(view, "grid", %{
      "op" => "window",
      "id" => "grid",
      "offset" => 0,
      "limit" => 50,
      "detail" => "text"
    })

    assert_push_event(view, "grid:window", %{rows: rows})
    assert [[73, [_name, ["2", _n, _band, :sequential, series]]], _retail] = rows
    assert length(series) == 12 and Enum.sum(series) == 2.0
  end

  test "a heading dropped in the pivot corner pivots a grouped grid, and the corner unpivots",
       %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Ccompany.name%2Cemail")

    # Without a group the drop groups first.
    render_hook(view, "grid", %{"op" => "pivot", "spec" => "company.name"})
    path = assert_patch(view)
    query = URI.decode_query(URI.parse(path).query)
    assert query["group"] == "company.name" and not Map.has_key?(query, "pivot")

    # Grouped, the next drop pivots: one column per name, a total, one row per company.
    render_hook(view, "grid", %{"op" => "pivot", "spec" => "name"})
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["pivot"] == "name"
    assert has_element?(view, "#grid-pivoted", "Pivoted by name")
    assert has_element?(view, "#grid-head-pv-total", "Total")
    assert has_element?(view, "#grid-head-pv-0", "Ada Lovelace")
    assert has_element?(view, "#grid-cell-Bilimbi_20Industries-pv-total", "2")
    assert has_element?(view, "#grid-cell-Bilimbi_20Retail-pv-total", "1")
    assert has_element?(view, "#grid-pagination-summary", "Showing 1 to 2 of 2 results")

    view |> element("#grid-unpivot") |> render_click()
    path = assert_patch(view)
    refute Map.has_key?(URI.decode_query(URI.parse(path).query), "pivot")
    refute has_element?(view, "#grid-pivoted")
    assert has_element?(view, "#grid-row-91")
  end
end
