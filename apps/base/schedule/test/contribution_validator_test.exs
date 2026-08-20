defmodule Bilimbi.Base.Schedule.ContributionValidatorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Schedule.ContributionValidator
  alias Bilimbi.Base.Schedule.TestWorker

  test "validates and indexes explicit durable definitions" do
    assert %{"base/perf.prune" => definition} =
             ContributionValidator.validate_contributions!([
               %{descriptor: descriptor(), payload: %{definitions: [attributes()]}}
             ])

    assert definition.owner == "base/perf"
    assert definition.owner_route == "/system/performance"
    assert definition.worker == TestWorker
    assert definition.misfire == :coalesce
  end

  test "rejects malformed cron, unknown timezones, and duplicate durable keys" do
    assert_raise ArgumentError, ~r/five-field cron/, fn ->
      validate!(Map.put(attributes(), :expression, "* * * * * *"))
    end

    assert_raise ArgumentError, ~r/not an IANA timezone/, fn ->
      validate!(Map.put(attributes(), :timezone, "Mars/Olympus"))
    end

    assert_raise ArgumentError, ~r/internal absolute path/, fn ->
      validate!(Map.put(attributes(), :owner_route, "https://example.test/performance"))
    end

    assert_raise ArgumentError, ~r/is owned by/, fn ->
      ContributionValidator.validate_contributions!([
        %{descriptor: descriptor(), payload: %{definitions: [attributes(), attributes()]}}
      ])
    end
  end

  defp validate!(attributes) do
    ContributionValidator.validate_contributions!([
      %{descriptor: descriptor(), payload: %{definitions: [attributes]}}
    ])
  end

  defp descriptor do
    %{id: "base/perf", otp_app: :bilimbi_base_schedule}
  end

  defp attributes do
    %{
      key: "base/perf.prune",
      name: "Prune performance history",
      expression: "15 1 * * *",
      timezone: "Etc/UTC",
      task_name: "Performance history prune",
      owner_route: "/system/performance",
      worker: TestWorker,
      args: %{"value" => 1},
      overlap: :forbid,
      misfire: :coalesce
    }
  end
end
