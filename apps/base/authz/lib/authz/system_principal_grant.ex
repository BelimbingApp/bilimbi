defmodule Bilimbi.Base.Authz.SystemPrincipalGrant do
  @moduledoc "One capability granted to a named system principal in one company."

  @enforce_keys [:id, :company_id, :principal, :capability, :granted_at]
  defstruct [:id, :company_id, :principal, :capability, :granted_at]

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer(),
          principal: String.t(),
          capability: String.t(),
          granted_at: NaiveDateTime.t()
        }
end
