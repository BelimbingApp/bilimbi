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
    :principal_name,
    :capability,
    :allowed,
    :created_at,
    :updated_at
  ]

  @type t :: %__MODULE__{}

  @doc """
  Builds the read model, naming the principal when the directory resolved it.

  `names` is keyed on the `{kind, id}` **pair**: a user and an employee can
  share an id, and keying on the id alone would show one of them the other's
  name. An absent key is not an error -- a principal outside the actor's
  tenant, or one whose module is not installed, keeps its durable id (#441).
  """
  @spec from_schema(PrincipalCapability.t(), %{{atom(), pos_integer()} => String.t()}) :: t()
  def from_schema(%PrincipalCapability{} = grant, names) when is_map(names) do
    %__MODULE__{from_schema(grant) | principal_name: principal_name(grant, names)}
  end

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

  defp principal_name(%{principal_type: type, principal_id: id}, names) do
    Map.get(names, {kind(type), id})
  end

  defp kind("user"), do: :user
  defp kind("agent"), do: :agent
  defp kind(_other), do: nil
end
