defmodule Bilimbi.Core.Address do
  @moduledoc """
  Public API for tenant-owned addresses and their business-owner attachments.

  Every operation receives an explicit tenant. Persisted Laravel polymorphic
  identity is hidden behind this module rather than exposed to callers.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address.Addressable
  alias Bilimbi.Core.Address.Schema
  alias Bilimbi.Core.Address.Summary
  alias Bilimbi.Core.Company

  @type error_reason :: :tenant_not_found | :address_not_found | :company_not_found

  @spec list_addresses(pos_integer()) :: {:ok, [Summary.t()]} | {:error, :tenant_not_found}
  def list_addresses(tenant_id) do
    with :ok <- validate_tenant(tenant_id) do
      addresses =
        from(address in Schema,
          where: address.tenant_id == ^tenant_id and is_nil(address.deleted_at),
          order_by: address.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, addresses}
    end
  end

  @spec get_address(pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :address_not_found}
  def get_address(tenant_id, address_id) do
    case get_schema(tenant_id, address_id) do
      nil -> {:error, :address_not_found}
      address -> {:ok, Summary.from_schema(address)}
    end
  end

  @spec create_address(pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :tenant_not_found | Ecto.Changeset.t()}
  def create_address(tenant_id, attributes) do
    with :ok <- validate_tenant(tenant_id),
         {:ok, address} <-
           tenant_id
           |> Schema.creation_changeset(attributes)
           |> Repo.insert() do
      {:ok, Summary.from_schema(address)}
    end
  end

  @spec update_address(pos_integer(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :address_not_found | Ecto.Changeset.t()}
  def update_address(tenant_id, address_id, attributes) do
    case get_schema(tenant_id, address_id) do
      nil ->
        {:error, :address_not_found}

      address ->
        case address |> Schema.update_changeset(attributes) |> Repo.update() do
          {:ok, updated} -> {:ok, Summary.from_schema(updated)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec delete_address(pos_integer(), pos_integer()) ::
          :ok | {:error, :address_not_found | Ecto.Changeset.t()}
  def delete_address(tenant_id, address_id) do
    case get_schema(tenant_id, address_id) do
      nil ->
        {:error, :address_not_found}

      address ->
        case address
             |> Ecto.Changeset.change(deleted_at: now())
             |> Repo.update() do
          {:ok, _address} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec attach_to_company(pos_integer(), pos_integer(), pos_integer(), map()) ::
          {:ok, :attached}
          | {:error, :address_not_found | :company_not_found | Ecto.Changeset.t()}
  def attach_to_company(tenant_id, address_id, company_id, attributes \\ %{}) do
    with %Schema{} <- get_schema(tenant_id, address_id),
         {:ok, _company} <- normalize_company_result(Company.get_company(tenant_id, company_id)),
         {:ok, _attachment} <-
           address_id
           |> Addressable.company_changeset(
             company_id,
             Company.addressable_identity(),
             attributes
           )
           |> Repo.insert() do
      {:ok, :attached}
    else
      nil -> {:error, :address_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_company_addresses(pos_integer(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_company_addresses(tenant_id, company_id) do
    with {:ok, _company} <- normalize_company_result(Company.get_company(tenant_id, company_id)) do
      company_addressable_identity = Company.addressable_identity()

      addresses =
        from(address in Schema,
          as: :address,
          where: address.tenant_id == ^tenant_id and is_nil(address.deleted_at),
          where:
            exists(
              from attachment in Addressable,
                where:
                  attachment.address_id == parent_as(:address).id and
                    attachment.addressable_type == ^company_addressable_identity and
                    attachment.addressable_id == ^company_id
            ),
          order_by: address.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, addresses}
    end
  end

  defp get_schema(tenant_id, address_id) do
    Repo.one(
      from address in Schema,
        where:
          address.id == ^address_id and address.tenant_id == ^tenant_id and
            is_nil(address.deleted_at)
    )
  end

  defp validate_tenant(tenant_id) do
    if Tenancy.get_tenant(tenant_id), do: :ok, else: {:error, :tenant_not_found}
  end

  defp normalize_company_result({:ok, company}), do: {:ok, company}
  defp normalize_company_result({:error, :not_found}), do: {:error, :company_not_found}

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
