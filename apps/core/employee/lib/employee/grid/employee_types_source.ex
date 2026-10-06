defmodule Bilimbi.Core.Employee.Grid.EmployeeTypesSource do
  @moduledoc """
  The employee types an actor's company can use: the system types and the
  company's own. Nothing for a system actor or an unaffiliated user.
  """

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Employee.EmployeeType

  @impl true
  def query(scope) do
    case Scope.actor(scope) do
      %Actor{type: :user, company_id: company_id} when is_integer(company_id) ->
        from(t in EmployeeType,
          where: t.company_id == ^company_id or is_nil(t.company_id),
          select: %{id: t.id, code: t.code, label: t.label, is_system: t.is_system}
        )

      %Actor{} ->
        from(t in EmployeeType,
          where: false,
          select: %{id: t.id, code: t.code, label: t.label, is_system: t.is_system}
        )
    end
  end
end
