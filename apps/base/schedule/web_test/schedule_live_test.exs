Code.require_file(Path.expand("../test/support/test_fixtures.ex", __DIR__))

Code.require_file(Path.expand("../test/support/workers.ex", __DIR__))

defmodule BilimbiWeb.ScheduleLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.DateTime, as: DateTimePolicy
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
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
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

    Repo.insert!(%Run{
      source: "scheduler",
      key: definition.key,
      name: definition.task_name,
      status: "succeeded",
      started_at: ~N[2026-08-20 01:30:00],
      finished_at: ~N[2026-08-20 01:30:02],
      runtime_ms: 2_000
    })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule")

    assert has_element?(view, "#schedule-board")
    assert has_element?(view, "#schedule-diagnostics")
    assert has_element?(view, "#schedule-task-test-schedule", "Test schedule")
    assert has_element?(view, "#schedule-task-test-schedule", definition.key)
    assert has_element?(view, "#schedule-task-test-schedule", definition.expression)
    assert has_element?(view, "#schedule-task-test-schedule", definition.timezone)
    assert has_element?(view, "#schedule-task-test-schedule a[href='/system/performance']")
    assert has_element?(view, "#schedule-task-test-schedule-next-due[data-follow-shell='true']")

    assert has_element?(
             view,
             "#schedule-task-test-schedule-last-started[data-follow-shell='true']"
           )

    refute has_element?(view, "#schedule-task-test-schedule button")

    assert render_click(view, "run_now", %{"key" => definition.key}) =~
             "You do not have permission to perform that action."

    assert render_click(view, "request_pause", %{"key" => definition.key}) =~
             "You do not have permission to perform that action."

    refute has_element?(view, "#schedule-command-confirm")

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

    # Enabling approves the reviewed definition to run unattended, so it
    # confirms through the shared dialog, which names the task and states
    # that it will run on its schedule at the fingerprint under review.
    refute has_element?(manager, "#schedule-task-test-schedule-enable[data-confirm]")
    manager |> element("#schedule-task-test-schedule-enable") |> render_click()

    assert_modal_dialog(
      manager,
      "schedule-command-confirm",
      "Task “#{definition.name}” will be enabled."
    )

    assert has_element?(
             manager,
             "#schedule-command-confirm-description",
             "It begins running automatically on its schedule (30 1 * * *, America/New_York) " <>
               "at definition fingerprint #{String.slice(Schedule.fingerprint(definition), 0, 12)}"
           )

    # Cancelling leaves the task not enabled.
    manager |> element("#schedule-command-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(manager, "#schedule-command-confirm")
    assert has_element?(manager, "#schedule-task-test-schedule-enable")
    assert {:error, :unreviewed} = Schedule.run_now(definition.key)

    # A confirm with nothing held is a stale click and does nothing.
    render_click(manager, "enable", %{"key" => definition.key})
    assert {:error, :unreviewed} = Schedule.run_now(definition.key)

    # Confirming enables it and reports the completed write as a success.
    manager |> element("#schedule-task-test-schedule-enable") |> render_click()

    assert has_element?(
             manager,
             "#schedule-command-confirm-confirm[phx-disable-with='Enabling…']",
             "Enable"
           )

    manager |> element("#schedule-command-confirm-confirm") |> render_click()
    refute has_element?(manager, "#schedule-command-confirm")
    assert has_element?(manager, "#flash-success", "Task enabled.")
    refute has_element?(manager, "#schedule-task-test-schedule-enable")
    assert has_element?(manager, "#schedule-task-test-schedule-pause")

    # Pausing cancels queued work, so it confirms through the shared dialog,
    # which names the task and says what resuming does not bring back.
    refute has_element?(manager, "#schedule-task-test-schedule-pause[data-confirm]")
    manager |> element("#schedule-task-test-schedule-pause") |> render_click()

    assert_modal_dialog(
      manager,
      "schedule-command-confirm",
      "Task “#{definition.name}” will be paused."
    )

    assert has_element?(manager, "dialog#schedule-command-confirm[role='alertdialog']")

    assert has_element?(
             manager,
             "#schedule-command-confirm-description",
             "Work already queued for it is cancelled before it starts."
           )

    # Cancelling keeps the task running.
    manager |> element("#schedule-command-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(manager, "#schedule-command-confirm")
    refute Repo.exists?(Suppression)

    # A confirm with nothing held is a stale click and does nothing.
    render_click(manager, "pause", %{"key" => definition.key})
    refute Repo.exists?(Suppression)

    # Confirming pauses it and reports the completed write as a success.
    manager |> element("#schedule-task-test-schedule-pause") |> render_click()

    assert has_element?(
             manager,
             "#schedule-command-confirm-confirm[phx-disable-with='Pausing…']",
             "Pause"
           )

    manager |> element("#schedule-command-confirm-confirm") |> render_click()
    refute has_element?(manager, "#schedule-command-confirm")
    assert has_element?(manager, "#flash-success", "Task paused.")
    assert Repo.exists?(Suppression)

    # Resuming loses nothing, so it runs on click without a confirmation.
    refute has_element?(manager, "#schedule-task-test-schedule-resume[data-confirm]")

    assert manager |> element("#schedule-task-test-schedule-resume") |> render_click() =~
             "Task resumed."

    refute Repo.exists?(Suppression)

    # Disabling confirms the same way and names its own consequence.
    manager |> element("#schedule-task-test-schedule-disable") |> render_click()

    assert_modal_dialog(
      manager,
      "schedule-command-confirm",
      "Task “#{definition.name}” will be disabled."
    )

    assert has_element?(
             manager,
             "#schedule-command-confirm-description",
             "stops queuing it until this definition is reviewed and enabled again."
           )

    manager |> element("#schedule-command-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(manager, "#schedule-command-confirm")
    assert has_element?(manager, "#schedule-task-test-schedule-pause")

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

  test "enabling a paused task says it stays paused until resumed", %{
    conn: conn,
    definition: definition
  } do
    grant_capabilities!([@view, @manage])
    {:ok, manager, _html} = conn |> log_in_as() |> live(~p"/system/schedule")

    for {button, verb} <- [enable: "Enable", pause: "Pause", disable: "Disable"] do
      manager |> element("#schedule-task-test-schedule-#{button}") |> render_click()
      manager |> element("#schedule-command-confirm-confirm", verb) |> render_click()
    end

    assert Repo.exists?(Suppression)
    manager |> element("#schedule-task-test-schedule-enable") |> render_click()

    assert_modal_dialog(
      manager,
      "schedule-command-confirm",
      "Task “#{definition.name}” will be enabled."
    )

    assert has_element?(
             manager,
             "#schedule-command-confirm-description",
             "Its definition is approved at fingerprint " <>
               "#{String.slice(Schedule.fingerprint(definition), 0, 12)}, the one under review, " <>
               "but the task stays paused and runs nothing until it is resumed."
           )

    refute has_element?(
             manager,
             "#schedule-command-confirm-description",
             "begins running automatically"
           )

    manager |> element("#schedule-command-confirm-confirm") |> render_click()
    assert has_element?(manager, "#flash-success", "Task enabled.")
    assert has_element?(manager, "#schedule-task-test-schedule-resume")
    assert Repo.exists?(Suppression)
    assert {:error, :suppressed} = Schedule.run_now(definition.key)
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

  test "history date filters bound the day the Started column shows, in every clock mode", %{
    conn: conn
  } do
    grant_capabilities!(@view)
    display_company_in!("Asia/Kuala_Lumpur")
    insert_boundary_runs!()

    # Company time: 23:30 UTC on the 20th reads 07:30 on the 21st, so the
    # start date that names that day selects it, and a UTC day would not.
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule?tab=history")
    assert has_element?(view, "#schedule-runs", "21/08/2026, 07:30 +08")
    assert has_element?(view, "#schedule-run-start-date + p", "Asia/Kuala_Lumpur")
    assert has_element?(view, "#schedule-run-end-date + p", "Asia/Kuala_Lumpur")
    assert has_element?(view, "label[for='schedule-run-start-date']", "Start date")
    refute has_element?(view, "label[for='schedule-run-start-date']", "UTC")

    filter_runs(view, %{"start_date" => "2026-08-21", "end_date" => ""})
    assert has_element?(view, "#schedule-runs", "Late on the twentieth")
    assert has_element?(view, "#schedule-runs", "Early on the twenty-first")
    assert has_element?(view, "#schedule-history-pagination-summary", "2 runs")

    filter_runs(view, %{"start_date" => "", "end_date" => "2026-08-20"})
    refute has_element?(view, "#schedule-runs", "Late on the twentieth")
    refute has_element?(view, "#schedule-runs", "Early on the twenty-first")
    assert has_element?(view, "#schedule-runs-empty", "No runs match the current filters.")

    # Stored UTC: the same rows read 20/08 and 21/08, and the same start date
    # now selects only the run that began on the UTC 21st.
    {:ok, :utc} = DateTimePolicy.put_mode(SettingsScope.user(91, 73, 41), :utc)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/system/schedule?tab=history&start_date=2026-08-21")

    assert has_element?(view, "#schedule-runs", "21/08/2026, 00:30 UTC")
    assert has_element?(view, "#schedule-run-start-date + p", "UTC")
    refute has_element?(view, "#schedule-runs", "Late on the twentieth")
    assert has_element?(view, "#schedule-runs", "Early on the twenty-first")
    assert has_element?(view, "#schedule-history-pagination-summary", ~r/\b1 run\b/)

    # Local time: the server does not know the browser's zone, so it bounds
    # the UTC text it rendered until the browser reports the zone it formats
    # in, and then bounds that zone's days.
    {:ok, :local} = DateTimePolicy.put_mode(SettingsScope.user(91, 73, 41), :local)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/system/schedule?tab=history&start_date=2026-08-21")

    assert has_element?(view, "#schedule-run-start-date + p", "UTC")
    refute has_element?(view, "#schedule-runs", "Late on the twentieth")

    render_hook(view, "browser_timezone", %{"timezone" => "Asia/Kuala_Lumpur"})
    assert has_element?(view, "#schedule-run-start-date + p", "Asia/Kuala_Lumpur")
    assert has_element?(view, "#schedule-runs", "Late on the twentieth")
    assert has_element?(view, "#schedule-history-pagination-summary", "2 runs")

    # A zone the server's database does not know cannot bound a query, so
    # the filter says UTC rather than pretending.
    render_hook(view, "browser_timezone", %{"timezone" => "Atlantis/Sunken"})
    assert has_element?(view, "#schedule-run-start-date + p", "UTC")
    refute has_element?(view, "#schedule-runs", "Late on the twentieth")
  end

  test "a saved clock change re-bounds the history the operator is looking at", %{conn: conn} do
    grant_capabilities!(@view)
    display_company_in!("Asia/Kuala_Lumpur")
    insert_boundary_runs!()

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/system/schedule?tab=history&start_date=2026-08-21")

    assert has_element?(view, "#schedule-run-start-date + p", "Asia/Kuala_Lumpur")
    assert has_element?(view, "#schedule-history-pagination-summary", "2 runs")

    # The shell's own hook saves the mode and halts the event before this view
    # sees it; the results still follow the Started column without a reload.
    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})

    assert has_element?(view, "#schedule-run-start-date + p", "UTC")
    refute has_element?(view, "#schedule-runs", "Late on the twentieth")
    assert has_element?(view, "#schedule-history-pagination-summary", ~r/\b1 run\b/)
  end

  test "a history holding more than one page still names the page it is on", %{conn: conn} do
    grant_capabilities!(@view)
    insert_runs!(26)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule?tab=history")

    assert has_element?(view, "#schedule-history-pagination-summary", "Page 1 of 2")
    assert has_element?(view, "#schedule-history-pagination-summary", "26 runs")
    refute has_element?(view, "#schedule-history-prev")
    assert has_element?(view, "#schedule-history-next")

    view |> element("#schedule-history-next") |> render_click()

    assert has_element?(view, "#schedule-history-pagination-summary", "Page 2 of 2")
    assert has_element?(view, "#schedule-history-prev")
    refute has_element?(view, "#schedule-history-next")
  end

  test "an inverted history date range is rejected rather than ignored", %{conn: conn} do
    grant_capabilities!(@view)
    insert_boundary_runs!()

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule?tab=history")

    filter_runs(view, %{"start_date" => "2026-08-21", "end_date" => "2026-08-20"})

    assert has_element?(view, "#schedule-history-invalid", "must not be after")
    refute has_element?(view, "#schedule-runs", "Late on the twentieth")
    refute has_element?(view, "#schedule-runs", "Early on the twenty-first")
    refute has_element?(view, "#schedule-history-pagination")
  end

  test "history toolbar filters round-trip through the URL", %{conn: conn} do
    grant_capabilities!(@view)
    insert_boundary_runs!()

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/schedule?tab=history")

    # The shared toolbar sends the same bounds a URL visit would carry.
    filter_runs(view, %{
      "search" => "",
      "status" => "",
      "start_date" => "2026-08-21",
      "end_date" => "",
      "page_size" => "25"
    })

    assert has_element?(view, "#schedule-history-pagination-summary", ~r/\b1 run\b/)

    patched = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert patched["tab"] == "history"
    assert patched["start_date"] == "2026-08-21"

    # The patched URL reloads to the same rows with the toolbar state retained.
    {:ok, reloaded, _html} =
      conn |> log_in_as() |> live(~p"/system/schedule?tab=history&start_date=2026-08-21")

    assert has_element?(reloaded, "#schedule-history-pagination-summary", ~r/\b1 run\b/)
    refute has_element?(reloaded, "#schedule-runs", "Late on the twentieth")
    assert has_element?(reloaded, "#schedule-runs", "Early on the twenty-first")
    assert has_element?(reloaded, "#schedule-run-start-date[value='2026-08-21']")
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
    assert has_element?(view, "#schedule-runs time[data-follow-shell='true']")
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

  # The company clock is what the product shows by default; the settings table
  # holds both the company zone and the account's clock mode.
  defp display_company_in!(timezone) do
    SettingsFixtures.create_settings_table!()

    {:ok, _value} =
      Settings.put("localization.timezone", timezone, SettingsScope.company(73, 41))

    {:ok, :company} = DateTimePolicy.put_mode(SettingsScope.user(91, 73, 41), :company)
    :ok
  end

  # The two instants straddle UTC midnight, so a timezone-shifted Started column
  # shows them on one day while the filters, bounding UTC days, would show two.
  defp insert_boundary_runs! do
    Repo.insert!(%Run{
      source: "scheduler",
      key: "test.schedule",
      name: "Late on the twentieth",
      status: "succeeded",
      started_at: ~N[2026-08-20 23:30:00]
    })

    Repo.insert!(%Run{
      source: "scheduler",
      key: "test.schedule",
      name: "Early on the twenty-first",
      status: "succeeded",
      started_at: ~N[2026-08-21 00:30:00]
    })
  end

  # The history pages at 25 rows, so a second page needs one run more than that.
  defp insert_runs!(count) do
    Enum.each(1..count, fn index ->
      Repo.insert!(%Run{
        source: "scheduler",
        key: "test.schedule",
        name: "Run #{index}",
        status: "succeeded",
        started_at: NaiveDateTime.add(~N[2026-08-20 01:00:00], index, :minute)
      })
    end)
  end

  defp filter_runs(view, params) do
    view
    |> form("#schedule-history-filters", run: params)
    |> render_change()
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
