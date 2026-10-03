defmodule Bilimbi.Base.Perf.ContributionsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  test "retention contributions validate under their worker owner" do
    # A package runtime loads only its dependency closure, not the whole workspace graph.
    descriptors =
      Enum.map([:bilimbi_base_authz, :bilimbi_base_perf], fn app ->
        Application.fetch_env!(app, :bilimbi_module)
      end)

    schedules = ContributionRegistry.build!(descriptors).consumers.schedule

    for {key, worker} <- [
          {"base/authz.decision_log_retention", Bilimbi.Base.Perf.AuthzRetentionWorker},
          {"base/perf.retention", Bilimbi.Base.Perf.RetentionWorker}
        ] do
      assert %{owner: "base/perf", worker: ^worker} = Map.fetch!(schedules, key)
    end

    assert [retention] =
             schedules
             |> Map.values()
             |> Enum.filter(&(&1.worker == Bilimbi.Base.Perf.AuthzRetentionWorker))

    assert retention.key == "base/authz.decision_log_retention"
    assert retention.expression == "23 3 * * *"
    assert retention.timezone == "Etc/UTC"
    assert retention.args == %{}
  end
end
