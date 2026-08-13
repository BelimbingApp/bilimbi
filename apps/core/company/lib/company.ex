defmodule Bilimbi.Core.Company do
  @moduledoc """
  Public API for the required Company business Module.

  The first compatibility slice exposes explicit primary-company identity
  while keeping Ecto schemas and query details private to this Module.
  """

  import Ecto.Query

  require Logger

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError, as: TenantInvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError, as: TenantNotProvisionedError
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.ExternalAccess
  alias Bilimbi.Core.Company.ExternalAccessSummary
  alias Bilimbi.Core.Company.LiveCompanyProof
  alias Bilimbi.Core.Company.PrimaryCompanyInvariantError
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.PrimaryCompanyNotProvisionedError
  alias Bilimbi.Core.Company.Relationship
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary

  @type lookup_error :: :not_provisioned | :invariant_violation | :database_unavailable
  @type access_lookup_error :: :not_found | :company_not_found | :relationship_not_found
  @list_limit 200

  @spec get_company(Scope.t(), pos_integer()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_company(%Scope{} = scope, company_id) do
    query =
      from company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      company -> {:ok, Summary.from_schema(company)}
    end
  end

  @doc """
  Locks one live Company row for a sibling workflow already inside the shared Repo transaction.

  The result proves only the Company identity. It is schema-free and valid only
  until the current `Bilimbi.Base.Repo` transaction commits or rolls back.
  Callers that acquire more than one module's records must lock Company rows
  first, then Employee rows, then User rows; within each kind, acquire ids in
  ascending order. Do not call this after taking an Employee or User row lock.

  Returns `{:error, :transaction_required}` when called outside an explicit
  shared Repo transaction. Missing, deleted, cross-tenant, and malformed
  Company identities all return the generic `{:error, :not_found}` outcome.
  """
  @spec lock_live_company(Scope.t(), term()) ::
          {:ok, LiveCompanyProof.t()} | {:error, :not_found | :transaction_required}
  def lock_live_company(%Scope{} = scope, company_id) do
    if Repo.in_transaction?() do
      lock_scoped_live_company(scope, company_id)
    else
      {:error, :transaction_required}
    end
  end

  @doc """
  Resolves a live company's tenant for the authenticated Web login edge.

  This is a deliberately narrow pre-scope lookup. Callers must already have
  authenticated the user associated with `company_id`, then prove the returned
  tenant through `Bilimbi.Base.Tenancy.scope/1`. Ordinary Company reads remain
  scope-required through `get_company/2` and `list_companies/1`.
  """
  @spec fetch_tenant_id_for_company(term()) :: {:ok, pos_integer()} | {:error, :not_found}
  def fetch_tenant_id_for_company(company_id) when is_integer(company_id) and company_id > 0 do
    query =
      from company in Schema,
        where: company.id == ^company_id and is_nil(company.deleted_at),
        select: company.tenant_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      tenant_id -> {:ok, tenant_id}
    end
  end

  def fetch_tenant_id_for_company(_company_id), do: {:error, :not_found}

  @doc """
  Lists live companies in the scope's tenant, ordered by id.

  Soft-deleted rows are excluded, matching `get_company/2`.
  """
  @spec list_companies(Scope.t()) :: {:ok, [Summary.t()]}
  def list_companies(%Scope{} = scope) do
    companies =
      from(company in Tenancy.scope_query(Schema, scope),
        where: is_nil(company.deleted_at),
        order_by: company.id
      )
      |> Repo.all()
      |> Enum.map(&Summary.from_schema/1)

    {:ok, companies}
  end

  @doc """
  Returns company ids owned by the scope's tenant, including soft-deleted rows.

  Belimbing's tenant-wide user list joins `companies` with a raw SQL left join,
  so Company's SoftDeletes scope never applies and users whose company is
  soft-deleted remain visible. Core User must not query `companies`; this
  Company-owned id list is the seam that preserves that visibility without
  leaking a queryable across the module boundary.
  """
  @spec list_tenant_company_ids(Scope.t()) :: {:ok, [pos_integer()]}
  def list_tenant_company_ids(%Scope{} = scope) do
    ids =
      from(company in Tenancy.scope_query(Schema, scope),
        order_by: company.id,
        select: company.id
      )
      |> Repo.all()

    {:ok, ids}
  end

  @spec platform_operator_company() :: {:ok, Summary.t()} | {:error, lookup_error()}
  def platform_operator_company do
    {:ok, PrimaryCompanyManager.platform_operator_company!()}
  rescue
    error in [TenantNotProvisionedError, PrimaryCompanyNotProvisionedError] ->
      Logger.info("platform operator is not fully provisioned: #{Exception.message(error)}")
      {:error, :not_provisioned}

    error in [TenantInvariantError, PrimaryCompanyInvariantError] ->
      Logger.error("platform operator identity is invalid: #{Exception.message(error)}")
      {:error, :invariant_violation}

    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("platform operator company lookup unavailable: #{Exception.message(error)}")
      {:error, :database_unavailable}
  end

  @doc """
  Assigns a tenant's primary company.

  The scope proves the tenant was live when the unit of work began. The manager
  still locks the tenant row inside its transaction, so a tenant deleted in the
  meantime is reported rather than assumed away.
  """
  @spec assign_primary_company(Scope.t(), pos_integer()) ::
          {:ok, PrimaryCompanyManager.assignment_status()}
          | {:error, PrimaryCompanyManager.assignment_error()}
  def assign_primary_company(%Scope{} = scope, company_id) do
    PrimaryCompanyManager.assign(Scope.tenant(scope), company_id)
  end

  @spec transfer_primary_company(Scope.t(), pos_integer()) ::
          {:ok, PrimaryCompanyManager.assignment_status()}
          | {:error, PrimaryCompanyManager.assignment_error()}
  def transfer_primary_company(%Scope{} = scope, company_id) do
    PrimaryCompanyManager.transfer(Scope.tenant(scope), company_id)
  end

  @spec addressable_identity() :: String.t()
  def addressable_identity, do: "App\\Core\\Company\\Models\\Company"

  @doc "Whether a department belongs to the requested tenant-owned company."
  @spec department_belongs_to_company?(Scope.t(), pos_integer(), pos_integer()) :: boolean()
  def department_belongs_to_company?(%Scope{} = scope, company_id, department_id)
      when is_integer(department_id) and department_id > 0 do
    case get_company(scope, company_id) do
      {:ok, _company} ->
        Repo.exists?(
          from(department in Department,
            where: department.id == ^department_id and department.company_id == ^company_id
          )
        )

      {:error, :not_found} ->
        false
    end
  end

  def department_belongs_to_company?(%Scope{}, _company_id, _department_id), do: false

  @spec provision_tenant(map(), map()) ::
          {:ok, %{tenant: Bilimbi.Base.Tenancy.Identity.t(), company: Summary.t()}}
          | {:error, Ecto.Changeset.t()}
  def provision_tenant(tenant_attributes, company_attributes) do
    PrimaryCompanyManager.provision_tenant(tenant_attributes, company_attributes)
  end

  @spec provision_platform_operator(String.t() | nil, map()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def provision_platform_operator(tenant_name, company_attributes) do
    PrimaryCompanyManager.provision_platform_operator(tenant_name, company_attributes)
  end

  @doc """
  Lists live external accesses granted by a tenant-owned company, oldest id first.

  Soft-deleted rows are excluded. The three-argument form requires a positive
  opaque `user_id`; Company does not resolve Core User rows. The result is capped.
  """
  @spec list_external_accesses(Scope.t(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_external_accesses(%Scope{} = scope, company_id) do
    list_company_accesses(scope, company_id, :all)
  end

  @spec list_external_accesses(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_external_accesses(%Scope{} = scope, company_id, user_id)
      when is_integer(user_id) and user_id > 0 do
    list_company_accesses(scope, company_id, user_id)
  end

  @doc """
  Lists live external accesses for one opaque user across live companies in the
  scope's tenant, oldest id first.

  The caller must already have proven that `user_id` belongs in this tenant
  (Core User's job). Company only filters by that identity against scoped
  companies and never queries `users`. The result is capped.
  """
  @spec list_external_accesses_for_user(Scope.t(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]}
  def list_external_accesses_for_user(%Scope{} = scope, user_id)
      when is_integer(user_id) and user_id > 0 do
    accesses =
      from(company in Tenancy.scope_query(Schema, scope),
        join: access in ExternalAccess,
        on: access.company_id == company.id,
        where:
          access.user_id == ^user_id and is_nil(access.deleted_at) and is_nil(company.deleted_at),
        order_by: access.id,
        limit: ^@list_limit,
        select: access
      )
      |> Repo.all()
      |> Enum.map(&ExternalAccessSummary.from_schema/1)

    {:ok, accesses}
  end

  @spec get_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()} | {:error, access_lookup_error()}
  def get_external_access(%Scope{} = scope, company_id, access_id) do
    case fetch_access(scope, company_id, access_id) do
      {:ok, access} -> {:ok, ExternalAccessSummary.from_schema(access)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec create_external_access(Scope.t(), pos_integer(), map()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, :company_not_found | :relationship_not_found | Ecto.Changeset.t()}
  def create_external_access(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- live_company(scope, company_id),
         {:ok, relationship_id} <- relationship_id_from(attributes),
         :ok <- prove_relationship(company_id, relationship_id) do
      company_id
      |> ExternalAccess.creation_changeset(attributes)
      |> persist_insert()
    end
  end

  @spec update_external_access(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, access_lookup_error() | Ecto.Changeset.t()}
  def update_external_access(%Scope{} = scope, company_id, access_id, attributes) do
    mutate_live_access(scope, company_id, access_id, fn access ->
      case maybe_prove_relationship(company_id, attributes) do
        :ok ->
          persist_update(ExternalAccess.update_changeset(access, attributes))

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @spec grant_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()} | {:error, access_lookup_error() | Ecto.Changeset.t()}
  def grant_external_access(%Scope{} = scope, company_id, access_id) do
    update_external_access(scope, company_id, access_id, %{
      is_active: true,
      access_granted_at: now()
    })
  end

  @spec revoke_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()} | {:error, access_lookup_error() | Ecto.Changeset.t()}
  def revoke_external_access(%Scope{} = scope, company_id, access_id) do
    update_external_access(scope, company_id, access_id, %{is_active: false})
  end

  @spec delete_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, access_lookup_error() | Ecto.Changeset.t()}
  def delete_external_access(%Scope{} = scope, company_id, access_id) do
    case mutate_live_access(scope, company_id, access_id, fn access ->
           persist_update(Ecto.Changeset.change(access, %{deleted_at: now()}))
         end) do
      {:ok, _summary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_company_accesses(scope, company_id, user_filter) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} = error ->
        error

      {:ok, _company} ->
        query =
          from(access in ExternalAccess,
            where: access.company_id == ^company_id and is_nil(access.deleted_at),
            order_by: access.id,
            limit: ^@list_limit
          )

        query =
          case user_filter do
            :all -> query
            user_id -> from(access in query, where: access.user_id == ^user_id)
          end

        {:ok, Enum.map(Repo.all(query), &ExternalAccessSummary.from_schema/1)}
    end
  end

  defp lock_scoped_live_company(_scope, company_id)
       when not (is_integer(company_id) and company_id > 0),
       do: {:error, :not_found}

  defp lock_scoped_live_company(%Scope{} = scope, company_id) do
    tenant_id = Scope.tenant_id(scope)

    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at),
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      %Schema{tenant_id: ^tenant_id, deleted_at: nil, id: ^company_id} ->
        {:ok, LiveCompanyProof.from_id(company_id)}

      _company ->
        {:error, :not_found}
    end
  end

  defp live_company(scope, company_id) do
    case get_company(scope, company_id) do
      {:ok, company} -> {:ok, company}
      {:error, :not_found} -> {:error, :company_not_found}
    end
  end

  defp fetch_access(scope, company_id, access_id) do
    case live_company(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _company} ->
        query =
          from(access in ExternalAccess,
            where:
              access.id == ^access_id and access.company_id == ^company_id and
                is_nil(access.deleted_at)
          )

        case Repo.one(query) do
          nil -> {:error, :not_found}
          access -> {:ok, access}
        end
    end
  end

  defp mutate_live_access(scope, company_id, access_id, fun) do
    Repo.transaction(fn ->
      case live_company(scope, company_id) do
        {:error, reason} ->
          Repo.rollback(reason)

        {:ok, _company} ->
          access =
            Repo.one(
              from(access in ExternalAccess,
                where:
                  access.id == ^access_id and access.company_id == ^company_id and
                    is_nil(access.deleted_at),
                lock: "FOR UPDATE"
              )
            )

          case access do
            nil ->
              Repo.rollback(:not_found)

            access ->
              case fun.(access) do
                {:ok, result} -> result
                {:error, reason} -> Repo.rollback(reason)
              end
          end
      end
    end)
    |> unwrap_mutation()
  end

  defp unwrap_mutation({:ok, result}), do: {:ok, result}
  defp unwrap_mutation({:error, reason}), do: {:error, reason}

  defp relationship_id_from(attributes) do
    case Map.get(attributes, :relationship_id) || Map.get(attributes, "relationship_id") do
      id when is_integer(id) and id > 0 -> {:ok, id}
      _other -> {:error, :relationship_not_found}
    end
  end

  defp maybe_prove_relationship(company_id, attributes) do
    case Map.get(attributes, :relationship_id) || Map.get(attributes, "relationship_id") do
      nil -> :ok
      id -> prove_relationship(company_id, id)
    end
  end

  defp prove_relationship(company_id, relationship_id) do
    exists? =
      Repo.exists?(
        from(relationship in Relationship,
          where:
            relationship.id == ^relationship_id and relationship.company_id == ^company_id and
              is_nil(relationship.deleted_at)
        )
      )

    if exists?, do: :ok, else: {:error, :relationship_not_found}
  end

  defp persist_insert(%Ecto.Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_insert(changeset) do
    case Repo.insert(changeset) do
      {:ok, access} -> {:ok, ExternalAccessSummary.from_schema(access)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp persist_update(%Ecto.Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_update(changeset) do
    case Repo.update(changeset) do
      {:ok, access} -> {:ok, ExternalAccessSummary.from_schema(access)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp now do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
