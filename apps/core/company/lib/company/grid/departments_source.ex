defmodule Bilimbi.Core.Company.Grid.DepartmentsSource do
  @moduledoc """
  The departments of the tenant's live companies, for the grid catalog,
  with the department type's code and name computed in. A department is in
  the tenant through its company, so the company subquery carries the
  tenant scope.
  """

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.Schema

  @impl true
  def query(scope) do
    companies =
      from(c in Tenancy.scope_query(Schema, scope),
        where: is_nil(c.deleted_at),
        select: %{id: c.id}
      )

    from(d in Department,
      join: c in subquery(companies),
      on: c.id == d.company_id,
      left_join: t in DepartmentType,
      on: t.id == d.department_type_id,
      select: %{
        id: d.id,
        company_id: d.company_id,
        head_id: d.head_id,
        status: d.status,
        type_code: t.code,
        type_name: t.name,
        created_at: d.created_at
      }
    )
  end
end
