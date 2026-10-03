defmodule Bilimbi.Base.Workflow.TestProcessAdapter do
  @moduledoc false
  @behaviour Bilimbi.Base.Workflow.ProcessAdapter
  alias Bilimbi.Base.{Authz, Repo}
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Workflow.TestSubjectSchema

  @impl true
  def authorize(_scope, %{facts: %{"marker" => "process_private"}}, _run, _operation),
    do: {:error, :process_owner_refused}

  def authorize(scope, subject, run, operation) do
    cond do
      run.input == %{"retired_attempt" => true} and operation == :complete ->
        {:error, :stale_owner_attempt}

      run.input == %{"effect_then_refuse" => true} and operation == :complete ->
        Repo.get!(TestSubjectSchema, subject.id)
        |> Ecto.Changeset.change(marker: "must_rollback")
        |> Repo.update!()

        {:error, :process_owner_refused}

      true ->
        resource =
          Resource.new!("example.record", subject.id,
            scope: scope,
            company_id: subject.company_id
          )

        if Authz.can(scope, "admin.test.record.view", resource).allowed,
          do: :ok,
          else: {:error, :missing_capability}
    end
  end
end
