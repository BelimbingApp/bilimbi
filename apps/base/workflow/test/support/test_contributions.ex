defmodule Bilimbi.Base.Workflow.TestContributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  alias Bilimbi.Base.Workflow.{
    TestAction,
    TestGuard,
    TestHumanActionHandler,
    TestListener,
    TestSubjectAdapter
  }

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
        human_actions: [
          %{
            key: "example.approve",
            label: "Approve",
            subject: "example.record",
            capability: "admin.test.record.view",
            handler: TestHumanActionHandler
          },
          %{
            key: "example.first",
            label: "Finish the first lane",
            subject: "example.record",
            capability: "admin.test.record.view",
            handler: TestHumanActionHandler,
            executor_key: "example.first"
          },
          %{
            key: "example.restricted",
            label: "Restricted",
            subject: "example.record",
            capability: "admin.test.record.approve",
            handler: TestHumanActionHandler
          }
        ],
        guards: [%{key: "example.guard", adapter: TestGuard, aliases: ["Legacy\\Example\\Guard"]}],
        actions: [
          %{key: "example.action", adapter: TestAction, aliases: ["Legacy\\Example\\Action"]}
        ],
        transition_listeners: [
          %{key: "example.notify", adapter: TestListener, subjects: ["example.record"]}
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
