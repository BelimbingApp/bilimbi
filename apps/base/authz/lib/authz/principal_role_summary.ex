defmodule Bilimbi.Base.Authz.PrincipalRoleSummary do
  @moduledoc "Stable read model for one principal-to-role assignment."

  alias Bilimbi.Base.Authz.PrincipalRole

  @enforce_keys [:id, :company_id, :principal_type, :principal_id, :role_id]
  defstruct [:id, :company_id, :principal_type, :principal_id, :role_id, :created_at]

  @type t :: %__MODULE__{}

  @doc false
  @spec from_schema(PrincipalRole.t()) :: t()
  def from_schema(%PrincipalRole{} = assignment) do
    %__MODULE__{
      id: assignment.id,
      company_id: assignment.company_id,
      principal_type: assignment.principal_type,
      principal_id: assignment.principal_id,
      role_id: assignment.role_id,
      created_at: assignment.created_at
    }
  end
end
