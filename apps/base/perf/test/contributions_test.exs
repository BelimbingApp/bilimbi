defmodule Bilimbi.Base.Perf.ContributionsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  test "installed retention schedules validate under their worker owner" do
    schedules = ContributionRegistry.build!().consumers.schedule

    for {key, worker} <- [
          {"base/authz.decision_log_retention", Bilimbi.Base.Perf.AuthzRetentionWorker},
          {"base/perf.retention", Bilimbi.Base.Perf.RetentionWorker}
        ] do
      assert %{owner: "base/perf", worker: ^worker} = Map.fetch!(schedules, key)
    end
  end
end
