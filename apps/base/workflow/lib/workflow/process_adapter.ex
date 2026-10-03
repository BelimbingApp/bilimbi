defmodule Bilimbi.Base.Workflow.ProcessAdapter do
  @moduledoc """
  Owner policy for durable coordination, executed in the shared Repo transaction.

  The locked Subject proves tenant identity. The plain run facts include its
  saved input, definition, subject and ID; for a new :start the ID is nil, and replay repeats :start with the saved ID. Enforce
  capabilities and business eligibility here, including current owner attempt
  or round binding on :complete. Operations are :start, :read, :complete,
  :supersede, :reconcile and :signal. :read never grants execution authority.
  Database effects may participate in the transaction; external effects must
  use their owner's durable dispatch. Do not acquire a run before the subject.
  """
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.Subject

  @callback authorize(Scope.t(), Subject.t(), map(), atom()) :: :ok | {:error, term()}
end
