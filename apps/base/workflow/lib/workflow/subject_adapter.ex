defmodule Bilimbi.Base.Workflow.SubjectAdapter do
  @moduledoc """
  Installed owners prove access and persist their own status.

  `load/3` starts with Tenancy.scope_query/2. For `:lock` it locks and rereads
  the owner row using FOR UPDATE on Bilimbi.Base.Repo. All callbacks execute
  in the kernel's shared Repo transaction. `authorize/3` enforces owner policy
  even when an edge has no capability; operations are :read, :transition,
  :record_initial, :record_comment and :adopt. Adoption requires explicit
  owner authority and real subject ownership, never a tenant guessed from history.

  `persist/4` writes only the proven subject, from the locked status to the
  requested status. Hooks and persistence must perform database effects only;
  external delivery belongs to durable coordination in a later slice.
  """
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.Subject

  @callback load(Scope.t(), pos_integer(), :read | :lock) :: {:ok, Subject.t()} | {:error, term()}
  @callback authorize(Scope.t(), Subject.t(), atom()) :: :ok | {:error, term()}
  @callback persist(Scope.t(), Subject.t(), String.t(), map()) :: :ok | {:error, term()}
end
