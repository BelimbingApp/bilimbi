defmodule Bilimbi.Base.Authz.RoleSummary do
  @moduledoc "Stable read model for an authorization role."

  alias Bilimbi.Base.Authz.Role

  @enforce_keys [:id, :name, :code, :is_system, :grant_all]
  defstruct [
    :id,
    :company_id,
    :name,
    :code,
    :description,
    :is_system,
    :grant_all,
    capability_count: 0,
    principal_count: 0
  ]

  @type t :: %__MODULE__{}

  @doc false
  @spec from_schema(Role.t(), non_neg_integer(), non_neg_integer()) :: t()
  def from_schema(%Role{} = role, capability_count \\ 0, principal_count \\ 0) do
    %__MODULE__{
      id: role.id,
      company_id: role.company_id,
      name: role.name,
      code: role.code,
      description: role.description,
      is_system: role.is_system,
      grant_all: role.grant_all,
      capability_count: capability_count,
      principal_count: principal_count
    }
  end
end
