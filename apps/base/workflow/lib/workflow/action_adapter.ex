defmodule Bilimbi.Base.Workflow.ActionAdapter do
  @moduledoc "Owner database action executed after status persistence; errors roll back everything."
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.Subject
  @callback execute(Scope.t(), Subject.t(), map(), map()) :: :ok | {:error, term()}
end
