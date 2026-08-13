defmodule Bilimbi.Base.Authz.RoleSummary do
  @moduledoc "Stable read model for an authorization role."

  alias Bilimbi.Base.Authz.Role

  @enforce_keys [:id, :name, :code, :is_system, :grant_all]
  defstruct [:id, :company_id, :name, :code, :description, :is_system, :grant_all]

  @type t :: %__MODULE__{}

  @doc false
  @spec from_schema(Role.t()) :: t()
  def from_schema(%Role{} = role) do
    %__MODULE__{
      id: role.id,
      company_id: role.company_id,
      name: role.name,
      code: role.code,
      description: role.description,
      is_system: role.is_system,
      grant_all: role.grant_all
    }
  end
end
