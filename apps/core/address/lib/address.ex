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
  alias Bilimbi.Core.Address.Detail
  alias Bilimbi.Core.Address.LinkedOwner
  alias Bilimbi.Core.Address.Page
  alias Bilimbi.Core.Address.Schema
  alias Bilimbi.Core.Address.Summary
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Geonames

  @default_page_size 25
  @maximum_page_size 100
  @address_sort_fields %{
    label: :label,
    country_iso: :country_iso,
    verification_status: :verification_status
  }
  @linked_owner_sort_fields ~w(type name kind is_primary priority valid_from valid_to)a

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

  @doc "Lists live tenant addresses through a bounded administration page."
  @spec list_addresses(Scope.t(), keyword()) :: Page.t(Summary.t())
  def list_addresses(%Scope{} = scope, opts) when is_list(opts) do
    opts =
      Keyword.validate!(opts,
        page: 1,
        page_size: @default_page_size,
        search: nil,
        sort_by: :label,
        sort_dir: :asc
      )

    query =
      Schema
      |> Tenancy.scope_query(scope)
      |> where([address], is_nil(address.deleted_at))
      |> maybe_search_addresses(search!(opts[:search]))

    page_query(query, opts)
  end

  @spec get_address(Scope.t(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :address_not_found}
  def get_address(%Scope{} = scope, address_id) do
    case get_schema(scope, address_id) do
      nil -> {:error, :address_not_found}
      address -> {:ok, Summary.from_schema(address)}
    end
  end

  @doc "Returns Address detail and its live Company or Employee owner projections."
  @spec get_address_detail(Scope.t(), pos_integer(), keyword()) ::
          {:ok, Detail.t()} | {:error, :address_not_found}
  def get_address_detail(%Scope{} = scope, address_id, opts \\ []) when is_list(opts) do
    opts = Keyword.validate!(opts, owner_sort_by: :type, owner_sort_dir: :asc)
    sort_by = owner_sort_by!(opts[:owner_sort_by])
    sort_dir = sort_dir!(opts[:owner_sort_dir])

    case get_schema(scope, address_id) do
      nil ->
        {:error, :address_not_found}

      address ->
        linked_owners = list_linked_owners(scope, address.id, sort_by, sort_dir)

        {:ok,
         Detail.from_schema(
           address,
           country_name(address.country_iso),
           admin1_name(address.admin1_code),
           linked_owners
         )}
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

  @doc "Creates a manual address and its Company attachment in one transaction."
  @spec create_and_attach_to_company(Scope.t(), pos_integer(), map(), map()) ::
          {:ok, Summary.t()} | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_and_attach_to_company(
        %Scope{} = scope,
        company_id,
        address_attributes,
        attachment_attributes \\ %{}
      )
      when is_map(address_attributes) and is_map(attachment_attributes) do
    Repo.transaction(fn ->
      _company = require_company!(scope, company_id)

      address =
        scope
        |> Scope.tenant_id()
        |> Schema.creation_changeset(address_attributes)
        |> Ecto.Changeset.put_change(:source, "manual")
        |> Ecto.Changeset.put_change(:verification_status, "unverified")
        |> Repo.insert()
        |> case do
          {:ok, address} -> address
          {:error, changeset} -> Repo.rollback(changeset)
        end

      attachment_attributes =
        cond do
          Map.has_key?(attachment_attributes, :valid_from) ->
            attachment_attributes

          Map.has_key?(attachment_attributes, "valid_from") ->
            attachment_attributes

          Enum.all?(Map.keys(attachment_attributes), &is_binary/1) ->
            Map.put(attachment_attributes, "valid_from", Date.utc_today())

          true ->
            Map.put(attachment_attributes, :valid_from, Date.utc_today())
        end

      case address.id
           |> Addressable.company_changeset(
             company_id,
             Company.addressable_identity(),
             attachment_attributes
           )
           |> Repo.insert() do
        {:ok, _attachment} -> Summary.from_schema(address)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, address} -> {:ok, address}
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

  @doc "Lists live tenant addresses not yet linked to the selected live Company."
  @spec list_available_company_addresses(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_available_company_addresses(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company_result(Company.get_company(scope, company_id)) do
      company_addressable_identity = Company.addressable_identity()

      addresses =
        from(address in Tenancy.scope_query(Schema, scope),
          where: is_nil(address.deleted_at),
          where:
            not exists(
              from(attachment in Addressable,
                where:
                  attachment.address_id == parent_as(:scoped).id and
                    attachment.addressable_type == ^company_addressable_identity and
                    attachment.addressable_id == ^company_id
              )
            ),
          order_by: [asc_nulls_last: address.label, asc: address.id]
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

  defp list_linked_owners(%Scope{} = scope, address_id, sort_by, sort_dir) do
    from(attachment in Addressable,
      where: attachment.address_id == ^address_id,
      order_by: attachment.id
    )
    |> Repo.all()
    |> Enum.flat_map(&linked_owner(scope, &1))
    |> Enum.sort(&linked_owner_before?(&1, &2, sort_by, sort_dir))
  end

  defp linked_owner(%Scope{} = scope, attachment) do
    company_identity = Company.addressable_identity()
    employee_identity = Employee.addressable_identity()

    case attachment.addressable_type do
      ^company_identity ->
        case Company.get_company(scope, attachment.addressable_id) do
          {:ok, company} -> [linked_owner(attachment, :company, company.name)]
          {:error, :not_found} -> []
        end

      ^employee_identity ->
        case Employee.get_employee(scope, attachment.addressable_id) do
          {:ok, employee} -> [linked_owner(attachment, :employee, employee.full_name)]
          {:error, :employee_not_found} -> []
        end

      _unknown_type ->
        []
    end
  end

  defp linked_owner(attachment, owner_type, name) do
    %LinkedOwner{
      attachment_id: attachment.id,
      owner_type: owner_type,
      owner_id: attachment.addressable_id,
      name: name,
      kind: attachment.kind || [],
      is_primary: attachment.is_primary,
      priority: attachment.priority,
      valid_from: attachment.valid_from,
      valid_to: attachment.valid_to
    }
  end

  defp linked_owner_before?(left, right, sort_by, sort_dir) do
    left_value = linked_owner_sort_value(left, sort_by)
    right_value = linked_owner_sort_value(right, sort_by)

    cond do
      left_value == right_value ->
        {left.owner_id, left.attachment_id} <= {right.owner_id, right.attachment_id}

      sort_dir == :asc ->
        left_value < right_value

      true ->
        left_value > right_value
    end
  end

  defp linked_owner_sort_value(owner, :type), do: Atom.to_string(owner.owner_type)
  defp linked_owner_sort_value(owner, :name), do: owner.name
  defp linked_owner_sort_value(owner, :kind), do: owner.kind |> Enum.sort() |> Enum.join(",")
  defp linked_owner_sort_value(owner, :is_primary), do: if(owner.is_primary, do: 1, else: 0)
  defp linked_owner_sort_value(owner, :priority), do: owner.priority || 0
  defp linked_owner_sort_value(owner, :valid_from), do: date_sort_value(owner.valid_from)
  defp linked_owner_sort_value(owner, :valid_to), do: date_sort_value(owner.valid_to)

  defp date_sort_value(nil), do: ""
  defp date_sort_value(date), do: Date.to_iso8601(date)

  defp country_name(nil), do: nil

  defp country_name(country_iso) do
    case Geonames.get_country(country_iso) do
      nil -> nil
      country -> country.country
    end
  end

  defp admin1_name(nil), do: nil

  defp admin1_name(admin1_code) do
    country_iso = admin1_code |> String.split(".", parts: 2) |> hd()

    case Enum.find(Geonames.list_admin1(country_iso), &(&1.code == admin1_code)) do
      nil -> nil
      admin1 -> admin1.name
    end
  end

  defp page_query(query, opts) do
    page = page!(opts[:page])
    page_size = page_size!(opts[:page_size])
    sort_field = sort_by!(opts[:sort_by])
    sort_direction = sort_dir!(opts[:sort_dir])
    total_entries = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_by(
        [address],
        ^[
          {sort_direction, sort_field},
          {:desc, :created_at},
          {:desc, :id}
        ]
      )
      |> offset(^((page - 1) * page_size))
      |> limit(^page_size)
      |> Repo.all()
      |> Enum.map(&Summary.from_schema/1)

    %Page{
      entries: entries,
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages(total_entries, page_size)
    }
  end

  defp maybe_search_addresses(query, nil), do: query

  defp maybe_search_addresses(query, search) do
    pattern = "%#{search}%"

    from(address in query,
      where:
        like(address.label, ^pattern) or like(address.line1, ^pattern) or
          like(address.locality, ^pattern) or like(address.postcode, ^pattern) or
          like(address.country_iso, ^pattern)
    )
  end

  defp search!(nil), do: nil

  defp search!(search) when is_binary(search) do
    case String.trim(search) do
      "" -> nil
      value -> value
    end
  end

  defp search!(value),
    do: raise(ArgumentError, "search must be a string or nil, got: #{inspect(value)}")

  defp sort_by!(value) do
    case Map.fetch(@address_sort_fields, value) do
      {:ok, field} ->
        field

      :error ->
        raise ArgumentError,
              "sort_by must be one of #{inspect(Map.keys(@address_sort_fields))}, got: #{inspect(value)}"
    end
  end

  defp owner_sort_by!(value) when value in @linked_owner_sort_fields, do: value

  defp owner_sort_by!(value) do
    raise ArgumentError,
          "owner_sort_by must be one of #{inspect(@linked_owner_sort_fields)}, got: #{inspect(value)}"
  end

  defp sort_dir!(value) when value in [:asc, :desc], do: value

  defp sort_dir!(value),
    do: raise(ArgumentError, "sort_dir must be :asc or :desc, got: #{inspect(value)}")

  defp page!(value) when is_integer(value) and value > 0, do: value

  defp page!(value),
    do: raise(ArgumentError, "page must be a positive integer, got: #{inspect(value)}")

  defp page_size!(value) when is_integer(value) and value in 1..@maximum_page_size, do: value

  defp page_size!(value) do
    raise ArgumentError,
          "page_size must be between 1 and #{@maximum_page_size}, got: #{inspect(value)}"
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)

  defp normalize_company_result({:ok, company}), do: {:ok, company}
  defp normalize_company_result({:error, :not_found}), do: {:error, :company_not_found}

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
