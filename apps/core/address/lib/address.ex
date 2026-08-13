defmodule Bilimbi.Core.Address do
  @moduledoc """
  Public API for tenant-owned addresses and their business-owner attachments.

  Every operation is performed under a `Bilimbi.Base.Tenancy.Scope`, so the
  tenant is resolved once by Base Tenancy rather than re-validated here on each
  call. Persisted Laravel polymorphic identity stays hidden behind this module
  rather than exposed to callers.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Address.Addressable
  alias Bilimbi.Core.Address.Schema
  alias Bilimbi.Core.Address.Summary
  alias Bilimbi.Core.Company

  @type error_reason ::
          :address_in_use | :address_not_found | :attachment_not_found | :company_not_found

  @doc "Address kinds supported by compatible Company attachments."
  @spec company_attachment_kinds() :: [String.t()]
  def company_attachment_kinds, do: Addressable.company_kinds()

  @spec list_addresses(Scope.t()) :: {:ok, [Summary.t()]}
  def list_addresses(%Scope{} = scope) do
    addresses =
      from(address in Tenancy.scope_query(Schema, scope),
        where: is_nil(address.deleted_at),
        order_by: address.id
      )
      |> Repo.all()
      |> Enum.map(&Summary.from_schema/1)

    {:ok, addresses}
  end

  @spec get_address(Scope.t(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :address_not_found}
  def get_address(%Scope{} = scope, address_id) do
    case get_schema(scope, address_id) do
      nil -> {:error, :address_not_found}
      address -> {:ok, Summary.from_schema(address)}
    end
  end

  @spec create_address(Scope.t(), map()) :: {:ok, Summary.t()} | {:error, Ecto.Changeset.t()}
  def create_address(%Scope{} = scope, attributes) do
    with {:ok, address} <-
           scope
           |> Scope.tenant_id()
           |> Schema.creation_changeset(attributes)
           |> Repo.insert() do
      {:ok, Summary.from_schema(address)}
    end
  end

  @spec update_address(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :address_not_found | Ecto.Changeset.t()}
  def update_address(%Scope{} = scope, address_id, attributes) do
    case get_schema(scope, address_id) do
      nil ->
        {:error, :address_not_found}

      address ->
        case address |> Schema.update_changeset(attributes) |> Repo.update() do
          {:ok, updated} -> {:ok, Summary.from_schema(updated)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec delete_address(Scope.t(), pos_integer()) ::
          :ok | {:error, :address_in_use | :address_not_found | Ecto.Changeset.t()}
  def delete_address(%Scope{} = scope, address_id) do
    Repo.transaction(fn ->
      address = lock_address!(scope, address_id)

      if attachment_exists?(address.id) do
        Repo.rollback(:address_in_use)
      end

      case address
           |> Ecto.Changeset.change(deleted_at: now())
           |> Repo.update() do
        {:ok, _address} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec attach_to_company(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, :attached}
          | {:error, :address_not_found | :company_not_found | Ecto.Changeset.t()}
  def attach_to_company(%Scope{} = scope, address_id, company_id, attributes \\ %{}) do
    Repo.transaction(fn ->
      address = lock_address!(scope, address_id)
      _company = require_company!(scope, company_id)

      case address.id
           |> Addressable.company_changeset(
             company_id,
             Company.addressable_identity(),
             attributes
           )
           |> Repo.insert() do
        {:ok, _attachment} -> :attached
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, :attached} -> {:ok, :attached}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Updates the compatible pivot metadata for one Company attachment."
  @spec update_company_attachment(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, :updated}
          | {:error,
             :address_not_found | :attachment_not_found | :company_not_found | Ecto.Changeset.t()}
  def update_company_attachment(%Scope{} = scope, address_id, company_id, attributes)
      when is_map(attributes) do
    Repo.transaction(fn ->
      address = lock_address!(scope, address_id)
      _company = require_company!(scope, company_id)
      attachments = lock_company_attachments!(address.id, company_id)

      Enum.each(attachments, fn attachment ->
        case attachment |> Addressable.update_changeset(attributes) |> Repo.update() do
          {:ok, _attachment} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

      :updated
    end)
    |> case do
      {:ok, :updated} -> {:ok, :updated}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes one Company's link to an address without deleting the address."
  @spec detach_from_company(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :address_not_found | :attachment_not_found | :company_not_found}
  def detach_from_company(%Scope{} = scope, address_id, company_id) do
    Repo.transaction(fn ->
      address = lock_address!(scope, address_id)
      _company = require_company!(scope, company_id)

      case Repo.delete_all(company_attachments_query(address.id, company_id)) do
        {0, nil} -> Repo.rollback(:attachment_not_found)
        {_deleted_count, nil} -> :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_company_addresses(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_company_addresses(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company_result(Company.get_company(scope, company_id)) do
      company_addressable_identity = Company.addressable_identity()

      addresses =
        from(address in Tenancy.scope_query(Schema, scope),
          where: is_nil(address.deleted_at),
          where:
            exists(
              from(attachment in Addressable,
                where:
                  attachment.address_id == parent_as(:scoped).id and
                    attachment.addressable_type == ^company_addressable_identity and
                    attachment.addressable_id == ^company_id
              )
            ),
          order_by: address.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, addresses}
    end
  end

  defp get_schema(%Scope{} = scope, address_id) do
    Repo.one(
      from(address in Tenancy.scope_query(Schema, scope),
        where: address.id == ^address_id and is_nil(address.deleted_at)
      )
    )
  end

  defp lock_address!(%Scope{} = scope, address_id) do
    case Repo.one(
           from(address in Tenancy.scope_query(Schema, scope),
             where: address.id == ^address_id and is_nil(address.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      nil -> Repo.rollback(:address_not_found)
      address -> address
    end
  end

  defp require_company!(%Scope{} = scope, company_id) do
    case Company.get_company(scope, company_id) do
      {:ok, company} -> company
      {:error, :not_found} -> Repo.rollback(:company_not_found)
    end
  end

  defp lock_company_attachments!(address_id, company_id) do
    attachments =
      address_id
      |> company_attachments_query(company_id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    case attachments do
      [] -> Repo.rollback(:attachment_not_found)
      attachments -> attachments
    end
  end

  defp company_attachments_query(address_id, company_id) do
    from(attachment in Addressable,
      where:
        attachment.address_id == ^address_id and
          attachment.addressable_type == ^Company.addressable_identity() and
          attachment.addressable_id == ^company_id
    )
  end

  defp attachment_exists?(address_id) do
    Repo.exists?(from(attachment in Addressable, where: attachment.address_id == ^address_id))
  end

  defp normalize_company_result({:ok, company}), do: {:ok, company}
  defp normalize_company_result({:error, :not_found}), do: {:error, :company_not_found}

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
