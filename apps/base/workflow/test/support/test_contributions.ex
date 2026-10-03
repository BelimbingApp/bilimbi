defmodule Bilimbi.Base.Workflow.TestContributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  alias Bilimbi.Base.Workflow.{TestAction, TestGuard, TestSubjectAdapter}
  @impl true
  def contributions do
    %{
      workflow: %{
        subjects: [
          %{
            key: "example.record",
            adapter: TestSubjectAdapter,
            aliases: ["Legacy\\Example\\Record"]
          }
        ],
        guards: [%{key: "example.guard", adapter: TestGuard, aliases: ["Legacy\\Example\\Guard"]}],
        actions: [
          %{key: "example.action", adapter: TestAction, aliases: ["Legacy\\Example\\Action"]}
        ],
        flows: [
          %{
            code: "example_flow",
            subject: "example.record",
            label: "Example flow",
            statuses: [
              %{code: "draft", label: "Draft"},
              %{code: "review", label: "Review"},
              %{code: "closed", label: "Closed"},
              %{code: "retired", label: "Retired", is_active: false}
            ],
            transitions: [
              %{
                from: "draft",
                to: "review",
                capability: "admin.test.record.view",
                guard: "example.guard",
                action: "example.action"
              },
              %{from: "draft", to: "closed"},
              %{from: "draft", to: "retired", is_active: false}
            ]
          }
        ]
      }
    }
  end
end
