defmodule Bilimbi.Core.Employee.EmployeeDirectoryProvider do
  @moduledoc """
  Names `:employee` identities for screens that reference an employee by id
  across an upward edge they cannot cross (a company department Head, a
  supervisor, a future Core audit actor) — ADR 0014.

  This is the counterpart to `PrincipalDirectoryProvider`, which answers the
  authz-principal `:agent` kind. Both resolve through the same tenant-scoped
  `get_tenant_employees/2`, but they answer different kinds because the kind
  records how the screen references the identity — as an authz principal versus
  as an employee — not a type filter. A department head is usually a regular
  employee and appears in no `principal_capabilities` row, so the `:agent`
  provider cannot name it; this one can.

  Resolution is partial and never raises for a business outcome: an id the scope
  cannot see — deleted, archived, or another tenant's — is omitted, not reported
  (ADR 0011). A raise here means the database is unreachable, which must not be
  swallowed into a screen of bare ids.
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Employee

  @impl true
  def principal_kind, do: :employee

  @impl true
  def names(%Scope{} = scope, ids) when is_list(ids) do
    {:ok, employees} = Employee.get_tenant_employees(scope, ids)

    Map.new(employees, fn {id, summary} -> {id, summary.full_name} end)
  end
end
