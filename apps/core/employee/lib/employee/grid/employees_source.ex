defmodule Bilimbi.Core.Employee.Grid.EmployeesSource do
  @moduledoc """
  The employees the scope's actor may list, for the grid catalog.

  The employees list is bounded to the actor's own company, and so is this
  source: it reads the actor's company from the sealed scope and returns
  that company's employees. A system actor, or a user with no company,
  reads none. A path from another table into employees therefore only
  reaches the actor's own company's people; the rest roll up to nothing.
  """

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Employee.Schema

  @impl true
  def query(scope) do
    case Scope.actor(scope) do
      %Actor{type: :user, company_id: company_id} when is_integer(company_id) ->
        from(e in Schema, where: e.company_id == ^company_id, select: ^select())

      %Actor{} ->
        from(e in Schema, where: false, select: ^select())
    end
  end

  defp select do
    [
      :id,
      :company_id,
      :department_id,
      :supervisor_id,
      :employee_number,
      :full_name,
      :short_name,
      :designation,
      :employee_type,
      :email,
      :mobile_number,
      :status,
      :employment_start,
      :employment_end,
      :created_at
    ]
  end
end
