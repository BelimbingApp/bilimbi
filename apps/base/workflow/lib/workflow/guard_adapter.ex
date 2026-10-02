defmodule Bilimbi.Base.Workflow.GuardAdapter do
  @moduledoc "Owner guard evaluated against the locked subject in the shared transaction."
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.Subject
  @callback check(Scope.t(), Subject.t(), map(), map()) :: :ok | {:error, term()}
end
