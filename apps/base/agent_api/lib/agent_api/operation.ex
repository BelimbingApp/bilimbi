defmodule Bilimbi.Base.AgentApi.Operation do
  @moduledoc """
  The handler behind an operation a module registers for agents.

  A handler is a thin adapter over its own module's facade: it reads the
  validated input, calls the facade with the scope it is given, and returns
  the facade's read model. It never takes an actor, tenant or company id
  from input, so the person the scope names is the person who did it, and
  the facade's own changesets, field restrictions and checks apply exactly
  as they do for the screen.

  `call/3` returns `{:ok, result}`, where the result is a read model (a
  struct, a map, a list of them) or a `Bilimbi.Base.AgentApi.Page` for a
  list operation. `Bilimbi.Base.AgentApi.Json` makes it JSON-ready, so a
  field the reader may not see stays a `Restricted` marker until then.
  Errors are the facade's own: `{:error, :not_found}`, `{:error,
  %Ecto.Changeset{}}`, or a domain refusal the dispatcher reports as
  rejected.

  A write operation also exports `preview/3`, which renders what the write
  would change from server data, so the person approving it sees the
  record's real before and after rather than the agent's account of it.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @type change :: %{field: String.t(), from: term(), to: term()}

  @callback call(key :: String.t(), Scope.t(), input :: map()) ::
              {:ok, term()} | {:error, term()}

  @callback preview(key :: String.t(), Scope.t(), input :: map()) ::
              {:ok, %{summary: String.t(), changes: [change()]}} | {:error, term()}

  @optional_callbacks preview: 3
end
