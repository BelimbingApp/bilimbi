defmodule Bilimbi.Base.Schedule.SchedulerStartupTest do
  # The scheduler's application starts before the deployment application
  # installs the contribution snapshot. Started in that window, the scheduler
  # must stay quiet, then poll once the snapshot arrives; a poll against a
  # registry that is unavailable keeps its warning. Clears the VM-wide
  # snapshot, so it cannot run beside a test that reads it.
  use Bilimbi.Base.Database.DataCase, async: false

  import ExUnit.CaptureLog

  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Administration
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.DefinitionReview
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Scheduler
  alias Bilimbi.Base.Schedule.TestWorker
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Crontab.CronExpression.Parser
  alias Ecto.Adapters.SQL.Sandbox

  @warning "schedule registry unavailable"

  setup do
    SettingsFixtures.create_settings_table!()
    AuditFixtures.create_audit_tables!()
    ContributionRegistry.clear_for_test!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "started before the snapshot is installed, it polls only once it is" do
    definition = definition()
    review!(definition)

    log =
      capture_log(fn ->
        pid = start_supervised!({Scheduler, name: :startup_test_scheduler})
        Sandbox.allow(Repo, self(), pid)
        _ = :sys.get_state(pid)
        assert Repo.aggregate(Occurrence, :count) == 0

        ContributionRegistry.put_consumers_for_test!(
          %{schedule: %{definition.key => definition}},
          "scheduler-startup"
        )

        # The signal makes the scheduler send itself the first poll; the
        # second system call queues behind that poll.
        _ = :sys.get_state(pid)
        _ = :sys.get_state(pid)
      end)

    refute log =~ @warning
    assert Repo.exists?(from(item in Occurrence, where: item.key == ^definition.key))
  end

  test "started after the snapshot is installed, it polls at once" do
    definition = definition()
    review!(definition)

    ContributionRegistry.put_consumers_for_test!(
      %{schedule: %{definition.key => definition}},
      "scheduler-startup"
    )

    log =
      capture_log(fn ->
        pid = start_supervised!({Scheduler, name: :startup_test_scheduler})
        Sandbox.allow(Repo, self(), pid)
        _ = :sys.get_state(pid)
      end)

    refute log =~ @warning
    assert Repo.exists?(from(item in Occurrence, where: item.key == ^definition.key))
  end

  test "a poll against an uninstalled registry still warns" do
    assert capture_log(fn -> assert :ok = Scheduler.poll() end) =~ @warning
  end

  defp definition do
    {:ok, cron} = Parser.parse("* * * * *", false, [:prior, :subsequent])

    %Definition{
      key: "startup.every-minute",
      name: "Start-up probe",
      expression: "* * * * *",
      cron: cron,
      timezone: "Etc/UTC",
      owner: "base/schedule",
      task_name: "Start-up probe",
      worker: TestWorker,
      args: %{"value" => 7},
      overlap: :allow,
      misfire: :coalesce
    }
  end

  defp review!(definition) do
    Repo.insert!(%DefinitionReview{
      source: "scheduler",
      key: definition.key,
      fingerprint: Administration.fingerprint(definition),
      enabled: true,
      reviewed_at: DateTime.utc_now()
    })
  end
end
