defmodule Bilimbi.Base.Tenancy do
  @moduledoc """
  Public API for tenant identity and isolation boundaries.

  Numeric tenant IDs have no runtime meaning. The platform operator is the one
  live tenant carrying the explicit database marker.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.InvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError
  alias Bilimbi.Base.Tenancy.Tenant

  @spec platform_operator() :: Identity.t() | nil
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
        Identity.from_schema(tenant)

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

  @spec require_platform_operator!() :: Identity.t()
  def require_platform_operator! do
    platform_operator() || raise NotProvisionedError
  end

  @spec platform_operator?(Identity.t()) :: boolean()
  def platform_operator?(%Identity{is_platform_operator: marked?}), do: marked?

  @spec get_tenant(pos_integer()) :: Identity.t() | nil
  def get_tenant(tenant_id) when is_integer(tenant_id) and tenant_id > 0 do
    case fetch_tenant(tenant_id) do
      {:ok, tenant} -> tenant
      {:error, _reason} -> nil
    end
  end

  @spec fetch_tenant(pos_integer()) ::
          {:ok, Identity.t()} | {:error, :not_found | :soft_deleted}
  def fetch_tenant(tenant_id) when is_integer(tenant_id) and tenant_id > 0 do
    case Repo.get(Tenant, tenant_id) do
      nil -> {:error, :not_found}
      %Tenant{deleted_at: nil} = tenant -> {:ok, Identity.from_schema(tenant)}
      %Tenant{} -> {:error, :soft_deleted}
    end
  end

  @doc """
  Reads a live tenant while holding its row lock for the current transaction.

  Callers that coordinate a multi-module write use this public operation rather
  than querying Base Tenancy's schema directly.
  """
  @spec lock_tenant(pos_integer()) ::
          {:ok, Identity.t()} | {:error, :not_found | :soft_deleted}
  def lock_tenant(tenant_id) when is_integer(tenant_id) and tenant_id > 0 do
    query = from tenant in Tenant, where: tenant.id == ^tenant_id, lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %Tenant{deleted_at: nil} = tenant -> {:ok, Identity.from_schema(tenant)}
      %Tenant{} -> {:error, :soft_deleted}
    end
  end

  @spec create_tenant(map()) :: {:ok, Identity.t()} | {:error, Ecto.Changeset.t()}
  def create_tenant(attributes) do
    attributes
    |> Tenant.creation_changeset()
    |> Repo.insert()
    |> map_tenant_result()
  end

  @spec provision_platform_operator(String.t() | nil) ::
          {:ok, Identity.t(), :created | :existing}
  def provision_platform_operator(name \\ nil) do
    name = normalized_name(name)

    case platform_operator() do
      %Identity{} = tenant ->
        {:ok, maybe_update_operator(tenant, name), :existing}

      nil ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        {count, _} =
          Repo.insert_all(
            Tenant,
            [
              %{
                name: name || "Platform operator",
                status: "active",
                is_platform_operator: true,
                created_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing
          )

        tenant = require_platform_operator!()
        tenant = if count == 0, do: maybe_update_operator(tenant, name), else: tenant
        {:ok, tenant, if(count == 1, do: :created, else: :existing)}
    end
  end

  defp maybe_update_operator(tenant, nil), do: tenant

  defp maybe_update_operator(tenant, name) do
    Tenant
    |> Repo.get!(tenant.id)
    |> Ecto.Changeset.change(name: name, status: "active")
    |> Repo.update!()
    |> Identity.from_schema()
  end

  defp map_tenant_result({:ok, tenant}), do: {:ok, Identity.from_schema(tenant)}
  defp map_tenant_result({:error, changeset}), do: {:error, changeset}

  defp normalized_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      value -> value
    end
  end

  defp normalized_name(_name), do: nil
end
