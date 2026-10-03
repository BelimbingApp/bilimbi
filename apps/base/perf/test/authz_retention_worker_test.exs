defmodule Bilimbi.Base.Perf.AuthzRetentionWorkerTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Perf.AuthzRetentionWorker
  alias Bilimbi.Base.Queue.Execution
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures

  setup do
    AuthzFixtures.create_authz_tables!()
    SettingsFixtures.create_settings_table!()

    [:bilimbi_base_authz, :bilimbi_base_perf]
    |> Enum.map(&Application.fetch_env!(&1, :bilimbi_module))
    |> ContributionRegistry.build!()
    |> ContributionRegistry.put_snapshot_for_test!()

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "scheduled worker deletes expired decisions and preserves retained decisions" do
    SettingsFixtures.put_stored_value!("authz.decision_log_retention_days", 10)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    [expired, retained] =
      for age <- [11, 9] do
        %{
          actor_type: "user",
          actor_id: 7,
          capability: "admin.authz.decision_log.view",
          allowed: false,
          reason_code: "denied_missing_capability",
          occurred_at: NaiveDateTime.add(now, -age * 86_400, :second)
        }
        |> DecisionLog.changeset()
        |> Repo.insert!()
      end

    execution = %Execution{job_id: 1, attempt: 1, max_attempts: 5, queue: "default"}

    assert :ok = AuthzRetentionWorker.handle_scheduled_job(%{}, execution)
    refute Repo.get(DecisionLog, expired.id)
    assert Repo.get!(DecisionLog, retained.id) == retained

    assert :ok = AuthzRetentionWorker.handle_scheduled_job(%{}, execution)
    assert Repo.all(DecisionLog) == [retained]
  end
end
