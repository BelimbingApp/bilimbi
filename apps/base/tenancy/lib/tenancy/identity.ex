defmodule Bilimbi.Base.Tenancy.Identity do
  @moduledoc """
  Stable tenant read model exposed by Base Tenancy.

  This is deliberately not the module's Ecto schema. Callers receive tenant
  meaning without coupling to persistence metadata, changesets, or queries.
  """

  alias Bilimbi.Base.Tenancy.Tenant

  @enforce_keys [:id, :name, :status, :is_platform_operator]
  defstruct [:id, :parent_id, :name, :status, :is_platform_operator]

  @type t :: %__MODULE__{
          id: pos_integer(),
          parent_id: pos_integer() | nil,
          name: String.t(),
          status: String.t(),
          is_platform_operator: boolean()
        }

  @doc false
  @spec from_schema(Tenant.t()) :: t()
  def from_schema(%Tenant{} = tenant) do
    %__MODULE__{
      id: tenant.id,
      parent_id: tenant.parent_id,
      name: tenant.name,
      status: tenant.status,
      is_platform_operator: tenant.is_platform_operator
    }
  end
end
