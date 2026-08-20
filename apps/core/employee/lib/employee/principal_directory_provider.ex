defmodule Bilimbi.Core.Employee.PrincipalDirectoryProvider do
  @moduledoc """
  Names `:agent` principals for Base screens, without Base querying Core.

  Base Authz stores users and employees in one `principal_capabilities` table
  and distinguishes them only by `principal_type`; an employee is the `agent`
  kind. This answers for that kind, as `Core.User`'s provider answers for
  `:user`.

  Scoping is `get_tenant_employees/2`, which resolves the scope's companies
  first — including archived ones, deliberately. A grant to an employee outlives
  their company being archived, and an operator who cannot see whose grant it is
  cannot revoke it.
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Employee

  @impl true
  def principal_kind, do: :agent

  @doc """
  Names the employees the scope can see, omitting the rest.

  No `rescue`, for the reason `Core.User`'s provider has none:
  `get_tenant_employees/2` answers `{:ok, map}` for every business outcome, so a
  raise means the database is unreachable or a table is missing. Swallowing that
  would render a screen of ids and report nothing (#359).
  """
  @impl true
  def names(%Scope{} = scope, ids) when is_list(ids) do
    {:ok, employees} = Employee.get_tenant_employees(scope, ids)

    Map.new(employees, fn {id, summary} -> {id, summary.full_name} end)
  end
end
