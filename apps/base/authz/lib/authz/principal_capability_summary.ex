defmodule Bilimbi.Base.Authz.PrincipalCapabilitySummary do
  @moduledoc "Stable read model for one persisted direct principal capability."

  alias Bilimbi.Base.Authz.PrincipalCapability

  @enforce_keys [
    :id,
    :company_id,
    :principal_type,
    :principal_id,
    :capability,
    :allowed
  ]
  defstruct [
    :id,
    :company_id,
    :principal_type,
    :principal_id,
    :capability,
    :allowed,
    :created_at,
    :updated_at
  ]

  @type t :: %__MODULE__{}

  @doc false
  @spec from_schema(PrincipalCapability.t()) :: t()
  def from_schema(%PrincipalCapability{} = grant) do
    %__MODULE__{
      id: grant.id,
      company_id: grant.company_id,
      principal_type: grant.principal_type,
      principal_id: grant.principal_id,
      capability: grant.capability_key,
      allowed: grant.is_allowed,
      created_at: grant.created_at,
      updated_at: grant.updated_at
    }
  end
end
