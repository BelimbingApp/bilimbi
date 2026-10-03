defmodule Bilimbi.Base.Workflow.TestHumanActionHandler do
  @moduledoc false
  @behaviour Bilimbi.Base.Workflow.HumanActionHandler
  import Ecto.Query
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Base.Workflow.TestSubjectSchema

  # Writes before deciding, so a refusal proves the gate rolls owner effects back.
  @impl true
  def handle(scope, subject, action, request) do
    query = from(s in Tenancy.scope_query(TestSubjectSchema, scope), where: s.id == ^subject.id)
    Repo.update_all(query, set: [marker: "human:" <> action.key])

    case request.payload do
      %{"refuse" => true} ->
        {:error, :handler_refused}

      %{"bad_outcome" => true} ->
        {:ok, %{output: :not_json}}

      payload ->
        {:ok,
         %{
           output: %{"handled" => action.key, "payload" => payload},
           result_ref: "owner-result:" <> Integer.to_string(subject.id)
         }}
    end
  end
end
