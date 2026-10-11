defmodule Bilimbi.Base.AgentApi.Operation do
  @moduledoc """
  The handler behind an operation a module registers for agents.

  A handler is a thin adapter over its own module's facade: it reads the
  validated input, calls the facade with the scope it is given, and returns
  the facade's read model. It never takes an actor or tenant id from input.
  An employer target is authorized through the Company facade; it never
  replaces the signed-in company. The scope names who did it, and
  the facade's own changesets, field restrictions and checks apply exactly
  as they do for the screen.

  `call/3` returns `{:ok, result}`, where the result is a read model (a
  struct, a map, a list of them) or a `Bilimbi.Base.AgentApi.Page` for a
  list operation. `Bilimbi.Base.AgentApi.Json` makes it JSON-ready, so a
  field the reader may not see stays a `Restricted` marker until then.
  Errors are the facade's own: `{:error, :not_found}`, `{:error,
  %Ecto.Changeset{}}`, or a domain refusal the dispatcher reports as
  rejected.

  A supported write declares `safe_write: true`, implements `preview/3`
  without mutation, and implements `commit/3` returning the domain record
  and its host-relative Bilimbi path. The person reviews validated changes,
  including domain defaults. Plans alone calls commit after checking the
  bound code. Commit calls the ordinary facade; it never skips a workflow.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @type change :: %{field: String.t(), from: term(), to: term()}

  @callback call(key :: String.t(), Scope.t(), input :: map()) ::
              {:ok, term()} | {:error, term()}

  @callback preview(key :: String.t(), Scope.t(), input :: map()) ::
              {:ok, %{summary: String.t(), changes: [change()]}} | {:error, term()}

  @callback commit(key :: String.t(), Scope.t(), input :: map()) ::
              {:ok, %{record: term(), path: String.t()}} | {:error, term()}

  @optional_callbacks preview: 3, commit: 3
end
