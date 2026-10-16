defmodule Bilimbi.Core.Employee.EmploymentOwner do
  @moduledoc """
  The module that owns employment facts once they leave Core Employee.

  Core keeps the legacy HR columns (number, type, status, dates, metadata) as
  a compatibility mirror until their owner, the mounted People domain, claims
  them. Core has no descriptor edge to that owner and must boot and behave
  identically without it, so the owner registers itself at runtime with
  `Bilimbi.Core.Employee.register_employment_owner/1` from its application
  start and unregisters on stop. With no owner registered, Core calls nothing.

  When an owner is registered, every Core write of a legacy employee row
  (create, update, subordinate assignment, delete and platform-orchestrator
  provisioning) calls `c:legacy_employee_written/2` inside the same Repo
  transaction, after Core's own locks (company, then the mapped person and
  affiliation, then the employee row) and after Core's write. Core reads the
  owner inside that transaction, after those locks, so a write that finds none
  registered takes no extra lock and calls nothing. Core passes the scope and
  one map, `%{employee_id: integer, person_id: integer | nil, affiliation_id:
  integer | nil}`, read in that transaction with no re-authorization (`nil`
  for both IDs when the row has no mapping), so the owner needs no
  list-capability read to store its mirror. The map may gain keys later;
  an owner ignores keys it does not know. The owner re-reads the HR facts of
  the row through the public Employee API and stores the result under that lock
  order, so Core's deprecated HR path does not leave the owner behind. A deleted row is absent
  from that read, and the IDs passed for it are the mapping that existed for
  the deleted row.

  A Core write already in flight when an owner registers may not call it:
  Core reads the owner once per write, and registration takes none of Core's
  locks. The owner must therefore run its adoption pass over
  `Bilimbi.Core.Employee.hr_handoff_page/3` after it registers, and a second
  pass after a grace period longer than any Core HR transaction (for example
  60 seconds). The second pass compares `updated_at` and includes newly
  inserted IDs, which covers in-flight updates and inserts. One pass alone
  does not close the race. Core keeps no reconcile state for it.

  The callback must not authorize again: Core accepted the write and the
  actor in `scope` already passed Core's checks. Returning `{:error, reason}`
  rolls the whole write back and Core returns `{:error, reason}` to its
  caller; return a changeset keyed by Core Employee field names for a
  refusal a page should show on the fact.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @doc "Called inside Core's write transaction after the legacy employee row was written or deleted."
  @callback legacy_employee_written(
              Scope.t(),
              %{
                required(:employee_id) => pos_integer(),
                required(:person_id) => pos_integer() | nil,
                required(:affiliation_id) => pos_integer() | nil,
                optional(atom()) => term()
              }
            ) :: :ok | {:error, term()}

  @doc "The owner's name, as Core's employee pages say who owns the HR facts."
  @callback name() :: String.t()

  @doc "The owner's page for one employee's employment facts, or nil when it has none."
  @callback employment_path(Scope.t(), company_id :: pos_integer(), employee_id :: pos_integer()) ::
              String.t() | nil

  @optional_callbacks employment_path: 3

  @key {__MODULE__, :registered}

  @doc false
  @spec register(module()) :: :ok | {:error, :invalid_owner | :already_registered}
  def register(module) when is_atom(module) do
    cond do
      not owner_module?(module) -> {:error, :invalid_owner}
      registered() in [nil, module] -> :persistent_term.put(@key, module)
      true -> {:error, :already_registered}
    end
  end

  def register(_module), do: {:error, :invalid_owner}

  @doc false
  @spec unregister(module()) :: :ok
  def unregister(module) do
    if registered() == module, do: :persistent_term.erase(@key)
    :ok
  end

  @doc false
  @spec registered() :: module() | nil
  def registered, do: :persistent_term.get(@key, nil)

  @doc false
  @spec ownership(module(), Scope.t(), pos_integer() | nil, pos_integer() | nil) ::
          %{name: String.t(), path: String.t() | nil}
  def ownership(owner, scope, company_id, employee_id) do
    path =
      if is_integer(company_id) and is_integer(employee_id) and
           function_exported?(owner, :employment_path, 3),
         do: owner.employment_path(scope, company_id, employee_id)

    %{name: owner.name(), path: path}
  end

  defp owner_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :legacy_employee_written, 2) and
      function_exported?(module, :name, 0)
  end
end
