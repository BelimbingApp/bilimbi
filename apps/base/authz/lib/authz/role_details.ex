defmodule Bilimbi.Base.Authz.RoleDetails do
  @moduledoc "Stable role detail with capability keys and scoped principal assignments."

  alias Bilimbi.Base.Authz.PrincipalRoleSummary
  alias Bilimbi.Base.Authz.RoleSummary

  @enforce_keys [:role, :capabilities, :principal_roles]
  defstruct [:role, :capabilities, :principal_roles]

  @type t :: %__MODULE__{
          role: RoleSummary.t(),
          capabilities: [String.t()],
          principal_roles: [PrincipalRoleSummary.t()]
        }
end
