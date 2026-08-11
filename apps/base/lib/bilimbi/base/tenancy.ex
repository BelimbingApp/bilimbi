defmodule Bilimbi.Base.Tenancy do
  @moduledoc """
  Public API for tenant identity and isolation boundaries.

  Numeric tenant IDs have no runtime meaning. The platform operator is the one
  live tenant carrying the explicit database marker.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.InvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError
  alias Bilimbi.Base.Tenancy.Tenant

  @spec platform_operator() :: Tenant.t() | nil
  def platform_operator do
    query =
      from tenant in Tenant,
        where: tenant.is_platform_operator,
        order_by: tenant.id,
        limit: 2

    case Repo.all(query) do
      [] ->
        nil

      [%Tenant{deleted_at: nil} = tenant] ->
        tenant

      [%Tenant{id: tenant_id}] ->
        raise InvariantError,
          message: "the platform-operator tenant is soft-deleted",
          details: %{tenant_id: tenant_id}

      tenants ->
        raise InvariantError,
          message: "multiple tenants are marked as the platform operator",
          details: %{tenant_ids: Enum.map(tenants, & &1.id)}
    end
  end

  @spec require_platform_operator!() :: Tenant.t()
  def require_platform_operator! do
    platform_operator() || raise NotProvisionedError
  end

  @spec platform_operator?(Tenant.t()) :: boolean()
  def platform_operator?(%Tenant{is_platform_operator: marked?}), do: marked?
end
