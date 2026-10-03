defmodule Bilimbi.Base.Workflow.TestProcessContributions do
  @moduledoc false
  alias Bilimbi.Base.Workflow.TestProcessAdapter

  def processes do
    [parallel(), dependencies(), gate(), retry()]
  end

  def parallel do
    %{
      key: "example.parallel",
      version: 1,
      subject: "example.record",
      adapter: TestProcessAdapter,
      steps:
        Enum.map(~w(first second third), fn key ->
          %{
            key: key,
            label: String.capitalize(key),
            executor_key: "example." <> key,
            input: [],
            metadata: %{"lane" => key}
          }
        end)
    }
  end

  def dependencies do
    %{
      key: "example.dependencies",
      version: 1,
      subject: "example.record",
      adapter: TestProcessAdapter,
      steps: [
        %{key: "first", label: "First", executor_key: "example.first"},
        %{key: "second", label: "Second", executor_key: "example.second"},
        %{key: "all", label: "All", dependencies: [%{step_key: "first"}, %{step_key: "second"}]},
        %{
          key: "any",
          label: "Any",
          dependency_mode: "any",
          dependencies: [%{step_key: "first"}, %{step_key: "second"}]
        },
        %{
          key: "impossible",
          label: "Impossible",
          dependencies: [%{step_key: "first", acceptable_outcomes: ["declined"]}]
        },
        %{key: "cascade", label: "Cascade", dependencies: [%{step_key: "impossible"}]}
      ]
    }
  end

  def gate do
    %{
      key: "example.gate",
      version: 1,
      subject: "example.record",
      adapter: TestProcessAdapter,
      steps: [%{key: "fact", label: "Fact", required_signal: "owner.ready", delay_seconds: 60}]
    }
  end

  def retry do
    %{
      key: "example.retry",
      version: 1,
      subject: "example.record",
      adapter: TestProcessAdapter,
      steps: [
        %{key: "work", label: "Work", executor_key: "example.work", max_attempts: 2},
        %{key: "after", label: "After", dependencies: [%{step_key: "work"}]}
      ]
    }
  end
end
