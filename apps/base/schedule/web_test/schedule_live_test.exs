Code.require_file(Path.expand("../test/support/test_fixtures.ex", __DIR__))

Code.require_file(Path.expand("../test/support/workers.ex", __DIR__))

defmodule BilimbiWeb.ScheduleLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.Suppression
  alias Bilimbi.Base.Schedule.TestFixtures, as: ScheduleFixtures
  alias Bilimbi.Base.Schedule.TestWorker
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Crontab.CronExpression.Parser

  @view "admin.system.schedule.view"
  @execute "admin.system.schedule.execute"
  @manage "admin.system.schedule.manage"

  setup do
    ScheduleFixtures.create_schedule_tables!()
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    original_snapshot = ContributionRegistry.snapshot!()
    definition = definition()

    ContributionRegistry.put_snapshot_for_test!(
      put_in(original_snapshot, [:consumers, :schedule], %{definition.key => definition})
    )

    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(original_snapshot) end)
    %{definition: definition}
  end

  test "requires authentication and the view capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/schedule")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/schedule")
  end

  test "view-only operators can inspect stable facts but cannot forge commands", %{
    conn: conn,
    definition: definition
  } do
    grant_capabilities!(@view)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule")

    assert has_element?(view, "#schedule-board")
    assert has_element?(view, "#schedule-diagnostics")
    assert has_element?(view, "#schedule-task-test-schedule", "Test schedule")
    assert has_element?(view, "#schedule-task-test-schedule", definition.key)
    assert has_element?(view, "#schedule-task-test-schedule", definition.expression)
    assert has_element?(view, "#schedule-task-test-schedule", definition.timezone)
    assert has_element?(view, "#schedule-task-test-schedule a[href='/system/performance']")
    refute has_element?(view, "#schedule-task-test-schedule button")

    assert render_click(view, "run_now", %{"key" => definition.key}) =~
             "You do not have permission to perform that action."

    assert render_click(view, "pause", %{"key" => definition.key}) =~
             "You do not have permission to perform that action."

    refute Repo.exists?(Occurrence)
    refute Repo.exists?(Suppression)
  end

  test "execute and manage remain distinct and every successful command is audited", %{
    conn: conn,
    definition: definition
  } do
    grant_capabilities!([@view, @manage])
    {:ok, manager, _html} = conn |> log_in_as() |> live(~p"/system/schedule")

    assert has_element?(manager, "#schedule-task-test-schedule-enable")
    refute has_element?(manager, "#schedule-task-test-schedule-run")
    assert render_click(manager, "enable", %{"key" => definition.key}) =~ "Task enabled."
    assert has_element?(manager, "#schedule-task-test-schedule-pause")

    assert render_click(manager, "pause", %{"key" => definition.key}) =~ "Task paused."
    assert Repo.exists?(Suppression)
    assert render_click(manager, "resume", %{"key" => definition.key}) =~ "Task resumed."
    refute Repo.exists?(Suppression)

    manager
    |> element("#schedule-tab-settings")
    |> render_click()

    assert has_element?(manager, "#schedule-retention-form")

    assert manager
           |> form("#schedule-retention-form", retention: %{days: "45"})
           |> render_submit() =~ "Retention saved."

    assert Settings.get("schedule.history.keep_days") == 45
    assert {:ok, scope} = Tenancy.scope(41)
    assert {:ok, actions} = Audit.list_actions(scope)

    assert Enum.map(actions, & &1.event) == [
             "schedule.task.enabled",
             "schedule.task.paused",
             "schedule.task.resumed",
             "schedule.retention.changed"
           ]

    manage_grant =
      scope
      |> Authz.list_principal_capabilities(
        principal_type: :user,
        principal_id: 91,
        page_size: 100
      )
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == @manage))

    assert {:ok, :removed} = Authz.remove_principal_capability(scope, manage_grant.id)
    grant_capabilities!(@execute)
    {:ok, executor, _html} = conn |> log_in_as() |> live(~p"/system/schedule")
    assert has_element?(executor, "#schedule-task-test-schedule-run")
    refute has_element?(executor, "#schedule-task-test-schedule-pause")
    assert render_click(executor, "run_now", %{"key" => definition.key}) =~ "Run queued."
    assert Repo.exists?(Occurrence)
  end

  test "already-mounted handlers reject revoked manage capability", %{
    conn: conn,
    definition: definition
  } do
    grant_capabilities!([@view, @manage])
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule")

    {:ok, scope} = Tenancy.scope(41)

    grant =
      scope
      |> Authz.list_principal_capabilities(
        principal_type: :user,
        principal_id: 91,
        page_size: 100
      )
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == @manage))

    assert {:ok, :removed} = Authz.remove_principal_capability(scope, grant.id)

    assert render_click(view, "enable", %{"key" => definition.key}) =~
             "You do not have permission to perform that action."

    assert {:error, :unreviewed} = Schedule.run_now(definition.key)
  end

  test "history refresh preserves URL filters and never discloses recorded output", %{conn: conn} do
    grant_capabilities!(@view)

    Repo.insert!(%Run{
      source: "scheduler",
      key: "test.schedule",
      name: "Visible run",
      status: "failed",
      started_at: ~N[2026-08-20 12:00:00],
      exit_code: 7,
      output_excerpt: "secret-output-must-not-render"
    })

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/system/schedule?tab=history&run_status=failed&page_size=25")

    assert has_element?(view, "#schedule-runs", "Visible run")
    assert has_element?(view, "#schedule-runs", "Exit 7")
    refute render(view) =~ "secret-output-must-not-render"

    Repo.insert!(%Run{
      source: "scheduler",
      key: "test.schedule",
      name: "Cross-process refresh",
      status: "failed",
      started_at: ~N[2026-08-20 13:00:00]
    })

    send(view.pid, :refresh)
    assert has_element?(view, "#schedule-runs", "Cross-process refresh")
    assert has_element?(view, "#schedule-run-status option[value='failed'][selected]")
    assert has_element?(view, "#schedule-run-page-size option[value='25'][selected]")
  end

  defp definition do
    {:ok, cron} = Parser.parse("30 1 * * *", false, [:prior, :subsequent])

    %Definition{
      key: "test.schedule",
      name: "Test schedule",
      expression: "30 1 * * *",
      cron: cron,
      timezone: "America/New_York",
      owner: "base/performance",
      owner_route: "/system/performance",
      task_name: "Test recurrence",
      worker: TestWorker,
      args: %{"value" => 7},
      overlap: :forbid,
      misfire: :coalesce
    }
  end
end
