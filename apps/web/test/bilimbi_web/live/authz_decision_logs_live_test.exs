defmodule BilimbiWeb.AuthzDecisionLogsLiveTest do
  @moduledoc """
  The decision log list.

  Logs are created the way the card requires — by asking `Authz.can/4` real
  questions, so the rows under test are the rows the system actually writes
  rather than fixtures shaped to suit the screen.
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

  # A decision the platform actually recorded, rather than a row shaped by hand.
  defp record_decision(scope, capability) do
    actor = Authz.actor(:user, 91, scope, 73)
    Authz.can(actor, capability)
  end

  defp open(conn, extra \\ []) do
    grant_capabilities!(["admin.authz.decision-log.list" | List.wrap(extra)])
    conn |> log_in_as() |> live(~p"/authz/decision-logs")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/decision-logs")
  end

  test "redirects away without admin.authz.decision-log.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/decision-logs")
  end

  test "lists recorded decisions and marks its nav row current", %{conn: conn, scope: scope} do
    record_decision(scope, "admin.user.list")

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#decision-logs", "admin.user.list")
    assert has_element?(view, "#nav-admin-authz-decision-log[aria-current='page']")
  end

  test "filters to denials, which is what this screen is opened for", %{
    conn: conn,
    scope: scope
  } do
    # Grant the one so it is genuinely allowed; the unknown capability fails
    # closed, so both rows are decisions the platform really made.
    grant_capabilities!("admin.authz.role.list")
    record_decision(scope, "admin.authz.role.list")
    record_decision(scope, "no.such.capability")

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "#decision-logs", "no.such.capability")
    assert has_element?(view, "#decision-logs", "admin.authz.role.list")

    view |> form("#logs-filters", %{"result" => "denied"}) |> render_change()

    assert has_element?(view, "#decision-logs", "no.such.capability")
    refute has_element?(view, "#decision-logs", "admin.authz.role.list")
  end

  test "search narrows to a capability", %{conn: conn, scope: scope} do
    record_decision(scope, "admin.user.list")
    record_decision(scope, "admin.company.list")

    {:ok, view, _html} = open(conn)

    view |> form("#logs-filters", %{"search" => "company"}) |> render_change()

    assert has_element?(view, "#decision-logs", "admin.company.list")
    refute has_element?(view, "#decision-logs", "admin.user.list")

    view |> form("#logs-filters", %{"search" => "zzz"}) |> render_change()
    assert render(view) =~ "No decisions match these filters."
  end

  test "defaults to newest first and keeps that when re-sorting time", %{
    conn: conn,
    scope: scope
  } do
    record_decision(scope, "admin.user.list")

    {:ok, view, _html} = open(conn)

    # A log read oldest-first is never what the reader wanted, so occurred_at
    # starts descending. Asserted through the rendered indicator, which is real
    # state -- reading it back off a helper would assert nothing.
    assert has_element?(view, "#logs-sort-occurred_at .hero-chevron-down")

    view |> element("#logs-sort-capability") |> render_click()
    assert %{"sort_by" => "capability", "sort_dir" => "asc"} = patched_params(view)

    view |> element("#logs-sort-occurred_at") |> render_click()
    assert %{"sort_by" => "occurred_at", "sort_dir" => "desc"} = patched_params(view)
  end

  test "an unrecognised sort or result in the URL falls back", %{conn: conn} do
    grant_capabilities!("admin.authz.decision-log.list")

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/authz/decision-logs?sort_by=drop_table&result=maybe&page=x")

    assert has_element?(view, "#logs-search")
    assert has_element?(view, "#logs-result option[value=''][selected]")
  end

  test "records the access check that opened it", %{conn: conn} do
    # Not a quirk of the test: reaching this page is itself an authorization
    # decision, so the log is never empty once someone has looked at it. Worth
    # pinning -- it means the empty state is effectively unreachable in
    # practice, and anyone reading these rows should expect to see their own
    # visit near the top.
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#decision-logs", "admin.authz.decision-log.list")
    refute render(view) =~ "No authorization decisions have been recorded"
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end
end
