defmodule Bilimbi.Core.Employee.Grid.Edges do
  @moduledoc """
  The edges Core Employee knows that no key pair expresses.

  An employee's type is a code, and a code names a system type or one the
  company defined under the same code. `employee_type/1` joins each
  employee to one type row, the company's own before the system one, so
  the `type` link is a `:one` link that never multiplies rows.
  """

  import Ecto.Query

  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.Schema

  @doc false
  def employee_type(_scope) do
    from(e in Schema,
      join: t in EmployeeType,
      on: t.code == e.employee_type and (t.company_id == e.company_id or is_nil(t.company_id)),
      distinct: [asc: e.id],
      order_by: [asc: e.id, asc_nulls_last: t.company_id],
      select: %{from_key: e.id, to_key: t.id}
    )
  end
end
