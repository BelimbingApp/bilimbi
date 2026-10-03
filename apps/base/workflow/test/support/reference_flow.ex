defmodule Bilimbi.Base.Workflow.ReferenceFlow do
  @moduledoc "Generic test owner used by the Workflow integration fixture."
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  import Ecto.Query

  alias Bilimbi.Base.{Authz, Repo, Tenancy}
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Workflow.{Subject, TestSubjectSchema}

  @behaviour Bilimbi.Base.Workflow.SubjectAdapter
  @behaviour Bilimbi.Base.Workflow.GuardAdapter
  @behaviour Bilimbi.Base.Workflow.ActionAdapter
  @behaviour Bilimbi.Base.Workflow.HumanActionHandler
  @behaviour Bilimbi.Base.Workflow.ProcessAdapter

  @impl true
  def contributions do
    %{
      workflow: %{
        subjects: [%{key: "reference.record", adapter: __MODULE__}],
        human_actions: [
          %{
            key: "reference.complete",
            label: "Complete review",
            subject: "reference.record",
            capability: "admin.reference.record.approve",
            handler: __MODULE__,
            executor_key: "example.first"
          }
        ],
        guards: [%{key: "reference.ready", adapter: __MODULE__}],
        actions: [%{key: "reference.marked", adapter: __MODULE__}],
        processes: [
          %{
            key: "reference.review",
            version: 1,
            subject: "reference.record",
            adapter: __MODULE__,
            steps: [%{key: "review", label: "Human review", executor_key: "example.first"}]
          }
        ],
        flows: [
          %{
            code: "reference_flow",
            subject: "reference.record",
            label: "Reference review",
            statuses: [
              %{code: "draft", label: "Draft"},
              %{code: "review", label: "In review"},
              %{code: "complete", label: "Complete"}
            ],
            transitions: [
              %{
                from: "draft",
                to: "review",
                capability: "admin.reference.record.approve",
                guard: "reference.ready",
                action: "reference.marked"
              },
              %{from: "review", to: "complete", capability: "admin.reference.record.approve"}
            ]
          }
        ]
      }
    }
  end

  @impl true
  def load(scope, id, mode) do
    query = from(record in Tenancy.scope_query(TestSubjectSchema, scope), where: record.id == ^id)
    query = if mode == :lock, do: from(record in query, lock: "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil ->
        {:error, :subject_not_found}

      row ->
        {:ok,
         %Subject{
           id: row.id,
           tenant_id: row.tenant_id,
           company_id: row.company_id,
           status: row.status,
           version: version(row),
           facts: %{}
         }}
    end
  end

  @impl true
  def authorize(scope, %{company_id: company_id} = subject, _operation)
      when not is_nil(company_id) do
    resource =
      Resource.new!("reference.record", subject.id,
        scope: scope,
        company_id: company_id
      )

    if Authz.can(scope, "admin.reference.record.approve", resource).allowed,
      do: :ok,
      else: {:error, :missing_capability}
  end

  def authorize(_scope, _subject, _operation), do: {:error, :missing_capability}

  @impl true
  def authorize(scope, subject, _run, _operation) do
    authorize(scope, subject, :process)
  end

  @impl true
  def persist(scope, subject, to, _context) do
    query =
      from(record in Tenancy.scope_query(TestSubjectSchema, scope),
        where: record.id == ^subject.id
      )

    case Repo.update_all(query, set: [status: to]) do
      {1, _} -> :ok
      _ -> {:error, :stale_subject}
    end
  end

  @impl true
  def check(_scope, _subject, _edge, _context), do: :ok

  @impl true
  def execute(scope, subject, _edge, _context) do
    query =
      from(record in Tenancy.scope_query(TestSubjectSchema, scope),
        where: record.id == ^subject.id
      )

    Repo.update_all(query, set: [marker: "transition-action"])
    :ok
  end

  @impl true
  def handle(scope, subject, action, _request) do
    query =
      from(record in Tenancy.scope_query(TestSubjectSchema, scope),
        where: record.id == ^subject.id
      )

    if action.key == "reference.complete" do
      Repo.update_all(query, set: [marker: "human-action"])
      {:ok, %{output: %{"reviewed" => true}, result_ref: "reference:#{subject.id}"}}
    else
      {:error, :unknown_action}
    end
  end

  defp version(row),
    do:
      :crypto.hash(
        :sha256,
        Enum.map_join(
          [row.id, row.tenant_id, row.company_id, row.status, row.marker],
          "|",
          &inspect/1
        )
      )
      |> Base.encode16(case: :lower)
end
