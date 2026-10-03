defmodule Bilimbi.Base.Workflow.TestAction do
  @moduledoc false
  @behaviour Bilimbi.Base.Workflow.ActionAdapter
  import Ecto.Query
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Base.Workflow.TestSubjectSchema
  @impl true
  def execute(scope, subject, _edge, context) do
    query = from s in Tenancy.scope_query(TestSubjectSchema, scope), where: s.id == ^subject.id
    Repo.update_all(query, set: [marker: "action_ran"])
    if context.input["refuse_action"], do: {:error, :action_refused}, else: :ok
  end
end
