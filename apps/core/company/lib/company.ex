defmodule Bilimbi.Core.Company do
  @moduledoc """
  Public API for the required Company business Module.

  The first compatibility slice exposes explicit primary-company identity
  while keeping Ecto schemas and query details private to this Module.
  """

  import Ecto.Query

  require Logger

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError, as: TenantInvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError, as: TenantNotProvisionedError
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.ExternalAccess
  alias Bilimbi.Core.Company.ExternalAccessSummary
  alias Bilimbi.Core.Company.IndexEntry
  alias Bilimbi.Core.Company.LegalEntityType
  alias Bilimbi.Core.Company.LiveCompanyProof
  alias Bilimbi.Core.Company.Page
  alias Bilimbi.Core.Company.PrimaryCompanyInvariantError
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.PrimaryCompanyNotProvisionedError
  alias Bilimbi.Core.Company.Relationship
  alias Bilimbi.Core.Company.RelationshipType
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary

  @type lookup_error :: :not_provisioned | :invariant_violation | :database_unavailable
  @type access_lookup_error :: :not_found | :company_not_found | :relationship_not_found
  @list_limit 200
  @company_page_sizes [25, 50, 100, 300]
  @company_sort_fields [:name, :status, :jurisdiction]
  @manage_across_tenant_capability "admin.company.tenant-wide.manage"

  @spec get_company(Scope.t(), pos_integer()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_company(%Scope{} = scope, company_id) when is_integer(company_id) and company_id > 0 do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      company -> {:ok, Summary.from_schema(company)}
    end
  end

  def get_company(%Scope{}, _company_id), do: {:error, :not_found}

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
      from(company in Schema,
        where: company.id == ^company_id and is_nil(company.deleted_at),
        select: company.tenant_id
      )

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
  Lists live tenant companies for the administration index.

  Supported options are `:search`, `:status`, `:sort_by`, `:sort_dir`, `:page`,
  and `:page_size`. Results include the parent display name and primary-company
  marker while keeping schema details inside Company.
  """
  @spec list_companies_page(Scope.t(), keyword()) :: Page.t()
  def list_companies_page(%Scope{} = scope, opts \\ []) when is_list(opts) do
    search = normalize_search(Keyword.get(opts, :search))
    status = normalize_company_status(Keyword.get(opts, :status))
    sort_by = normalize_company_sort_by(Keyword.get(opts, :sort_by))
    sort_dir = normalize_sort_dir(Keyword.get(opts, :sort_dir))
    page = positive_integer(Keyword.get(opts, :page)) || 1
    page_size = normalize_company_page_size(Keyword.get(opts, :page_size))

    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: is_nil(company.deleted_at)
      )
      |> filter_companies_by_search(search)
      |> filter_companies_by_status(status)

    total_entries = Repo.one(from(company in query, select: count(company.id)))
    total_pages = total_pages(total_entries, page_size)

    entries =
      query
      |> order_companies(sort_by, sort_dir)
      |> offset(^((page - 1) * page_size))
      |> limit(^page_size)
      |> with_company_index_context()
      |> Repo.all()
      |> Enum.map(fn %{company: company, parent_name: parent_name, is_primary: is_primary?} ->
        company
        |> Summary.from_schema()
        |> IndexEntry.from_summary(parent_name, is_primary?)
      end)

    %Page{
      entries: entries,
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @doc """
  Lists the live companies an actor may target for an authorized operation.

  The operation capability and company reach are independent: the tenant-wide
  capability expands the actor's reach but never authorizes an operation by
  itself. Every returned company remains inside the actor's validated tenant
  scope.
  """
  @spec list_selectable_companies(Actor.t(), String.t()) ::
          {:ok, [Summary.t()]} | {:error, :unauthorized}
  def list_selectable_companies(%Actor{} = actor, operation_capability)
      when is_binary(operation_capability) do
    if capability_allowed?(actor, operation_capability) do
      {:ok, companies} = list_companies(actor.scope)

      if capability_allowed?(actor, @manage_across_tenant_capability) do
        {:ok, companies}
      else
        {:ok, Enum.filter(companies, &(&1.id == actor.company_id))}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Authorizes one live company as the target of an actor's operation.

  Missing, deleted, and cross-tenant companies are indistinguishable. A
  sibling company additionally requires the explicit tenant-wide reach
  capability.
  """
  @spec authorize_company_target(Actor.t(), term(), String.t()) ::
          {:ok, Summary.t()} | {:error, :not_found | :unauthorized}
  def authorize_company_target(%Actor{} = actor, company_id, operation_capability)
      when is_integer(company_id) and company_id > 0 and is_binary(operation_capability) do
    with true <- capability_allowed?(actor, operation_capability),
         {:ok, company} <- get_company(actor.scope, company_id),
         true <-
           company.id == actor.company_id or
             capability_allowed?(actor, @manage_across_tenant_capability) do
      {:ok, company}
    else
      false -> {:error, :unauthorized}
      {:error, :not_found} = error -> error
    end
  end

  def authorize_company_target(%Actor{}, _company_id, operation_capability)
      when is_binary(operation_capability),
      do: {:error, :not_found}

  defp capability_allowed?(actor, capability) do
    Authz.can(actor, capability).allowed
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
  Creates a company under the scope's tenant.

  When `is_primary: true` is passed, the write is executed inside a transaction
  and atomically designated as that tenant's primary company.
  """
  @spec create_company(Scope.t(), map(), keyword()) ::
          {:ok, Summary.t()} | {:error, Ecto.Changeset.t()}
  def create_company(%Scope{} = scope, attributes, opts \\ []) do
    tenant_id = Scope.tenant_id(scope)
    is_primary? = Keyword.get(opts, :is_primary, false)

    Repo.transaction(fn ->
      changeset = Schema.creation_changeset(tenant_id, attributes)

      case Repo.insert(changeset) do
        {:ok, company} ->
          if is_primary? do
            case assign_primary_company(scope, company.id) do
              {:ok, _status} ->
                Summary.from_schema(company)

              {:error, reason} ->
                Repo.rollback(reason)
            end
          else
            Summary.from_schema(company)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> unwrap_mutation()
  end

  @doc """
  Updates a live Company record scoped to the caller's tenant.
  """
  @spec update_company(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_company(%Scope{} = scope, company_id, attributes)
      when is_integer(company_id) and company_id > 0 and is_map(attributes) do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      company ->
        company
        |> Schema.update_changeset(attributes)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, Summary.from_schema(updated)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def update_company(%Scope{}, _company_id, _attributes), do: {:error, :not_found}

  @doc """
  Soft-deletes a live Company row scoped to the caller's tenant.

  The tenant primary company cannot be deleted through this API; callers must
  explicitly transfer the primary assignment first.
  """
  @spec delete_company(Scope.t(), pos_integer()) ::
          :ok | {:error, :not_found | :primary_company | Ecto.Changeset.t()}
  def delete_company(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    case Repo.transaction(fn ->
           query =
             from(company in Tenancy.scope_query(Schema, scope),
               where: company.id == ^company_id and is_nil(company.deleted_at),
               lock: "FOR UPDATE"
             )

           case Repo.one(query) do
             nil ->
               Repo.rollback(:not_found)

             %Schema{} = company ->
               if primary_company?(scope, company.id) do
                 Repo.rollback(:primary_company)
               else
                 company
                 |> Ecto.Changeset.change(deleted_at: now())
                 |> Repo.update()
                 |> case do
                   {:ok, _company} -> :ok
                   {:error, changeset} -> Repo.rollback(changeset)
                 end
               end
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_company(%Scope{}, _company_id), do: {:error, :not_found}

  @doc """
  Lists live direct child companies (subsidiaries) for a given parent company in the caller's tenant.
  """
  @spec list_child_companies(Scope.t(), pos_integer()) :: {:ok, [Summary.t()]}
  def list_child_companies(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    companies =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.parent_id == ^company_id and is_nil(company.deleted_at),
        order_by: company.id
      )
      |> Repo.all()
      |> Enum.map(&Summary.from_schema/1)

    {:ok, companies}
  end

  def list_child_companies(%Scope{}, _company_id), do: {:ok, []}

  @doc """
  Returns whether the company is designated as the primary company for the scope's tenant.
  """
  @spec primary_company?(Scope.t(), pos_integer()) :: boolean()
  def primary_company?(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    tenant_id = Scope.tenant_id(scope)

    from(primary in "tenant_primary_companies",
      where: primary.tenant_id == ^tenant_id and primary.company_id == ^company_id,
      select: count(primary.company_id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  def primary_company?(%Scope{}, _company_id), do: false

  # ============================================================================
  # Legal Entity Types
  # ============================================================================

  @spec list_legal_entity_types(keyword()) :: {:ok, [LegalEntityType.t()]}
  def list_legal_entity_types(opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, :name)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)

    query = from(t in LegalEntityType)

    query =
      case sort_by do
        :code -> from(t in query, order_by: [{^sort_dir, t.code}])
        :is_active -> from(t in query, order_by: [{^sort_dir, t.is_active}, {:asc, t.name}])
        _ -> from(t in query, order_by: [{^sort_dir, t.name}])
      end

    {:ok, Repo.all(query)}
  end

  @spec get_legal_entity_type(pos_integer()) :: {:ok, LegalEntityType.t()} | {:error, :not_found}
  def get_legal_entity_type(id) when is_integer(id) and id > 0 do
    case Repo.get(LegalEntityType, id) do
      nil -> {:error, :not_found}
      type -> {:ok, type}
    end
  end

  def get_legal_entity_type(_id), do: {:error, :not_found}

  @spec create_legal_entity_type(map()) ::
          {:ok, LegalEntityType.t()} | {:error, Ecto.Changeset.t()}
  def create_legal_entity_type(attrs) do
    %LegalEntityType{}
    |> LegalEntityType.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_legal_entity_type(pos_integer() | LegalEntityType.t(), map()) ::
          {:ok, LegalEntityType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_legal_entity_type(%LegalEntityType{} = type, attrs) do
    type
    |> LegalEntityType.update_changeset(attrs)
    |> Repo.update()
  end

  def update_legal_entity_type(id, attrs) when is_integer(id) and id > 0 do
    case Repo.get(LegalEntityType, id) do
      nil -> {:error, :not_found}
      type -> update_legal_entity_type(type, attrs)
    end
  end

  def update_legal_entity_type(_id, _attrs), do: {:error, :not_found}

  @spec toggle_legal_entity_type_active(pos_integer()) ::
          {:ok, LegalEntityType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def toggle_legal_entity_type_active(id) when is_integer(id) and id > 0 do
    case Repo.get(LegalEntityType, id) do
      nil ->
        {:error, :not_found}

      type ->
        type
        |> Ecto.Changeset.change(is_active: not type.is_active)
        |> Repo.update()
    end
  end

  def toggle_legal_entity_type_active(_id), do: {:error, :not_found}

  @spec delete_legal_entity_type(pos_integer()) :: :ok | {:error, :not_found | :in_use}
  def delete_legal_entity_type(id) when is_integer(id) and id > 0 do
    case Repo.get(LegalEntityType, id) do
      nil ->
        {:error, :not_found}

      type ->
        in_use? =
          Repo.exists?(
            from(c in Schema, where: c.legal_entity_type_id == ^id and is_nil(c.deleted_at))
          )

        if in_use? do
          {:error, :in_use}
        else
          case Repo.delete(type) do
            {:ok, _} -> :ok
            {:error, _} -> {:error, :in_use}
          end
        end
    end
  end

  def delete_legal_entity_type(_id), do: {:error, :not_found}

  # ============================================================================
  # Department Types
  # ============================================================================

  @spec list_department_types(keyword()) :: {:ok, [DepartmentType.t()]}
  def list_department_types(opts \\ []) do
    category = Keyword.get(opts, :category)
    active_only = Keyword.get(opts, :active_only, false)
    sort_by = Keyword.get(opts, :sort_by, :name)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)

    query = from(t in DepartmentType)

    query =
      if category in DepartmentType.categories(),
        do: from(t in query, where: t.category == ^category),
        else: query

    query = if active_only, do: from(t in query, where: t.is_active == true), else: query

    query =
      case sort_by do
        :code ->
          from(t in query, order_by: [{^sort_dir, t.code}])

        :category ->
          from(t in query, order_by: [{^sort_dir, t.category}, {:asc, t.name}])

        :is_active ->
          from(t in query, order_by: [{^sort_dir, t.is_active}, {:asc, t.name}])

        _ ->
          from(t in query, order_by: [{^sort_dir, t.name}])
      end

    {:ok, Repo.all(query)}
  end

  @spec get_department_type(pos_integer()) :: {:ok, DepartmentType.t()} | {:error, :not_found}
  def get_department_type(id) when is_integer(id) and id > 0 do
    case Repo.get(DepartmentType, id) do
      nil -> {:error, :not_found}
      type -> {:ok, type}
    end
  end

  def get_department_type(_id), do: {:error, :not_found}

  @spec create_department_type(map()) ::
          {:ok, DepartmentType.t()} | {:error, Ecto.Changeset.t()}
  def create_department_type(attrs) do
    %DepartmentType{}
    |> DepartmentType.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_department_type(pos_integer() | DepartmentType.t(), map()) ::
          {:ok, DepartmentType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_department_type(%DepartmentType{} = type, attrs) do
    type
    |> DepartmentType.update_changeset(attrs)
    |> Repo.update()
  end

  def update_department_type(id, attrs) when is_integer(id) and id > 0 do
    case Repo.get(DepartmentType, id) do
      nil -> {:error, :not_found}
      type -> update_department_type(type, attrs)
    end
  end

  def update_department_type(_id, _attrs), do: {:error, :not_found}

  @spec toggle_department_type_active(pos_integer()) ::
          {:ok, DepartmentType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def toggle_department_type_active(id) when is_integer(id) and id > 0 do
    case Repo.get(DepartmentType, id) do
      nil ->
        {:error, :not_found}

      type ->
        type
        |> Ecto.Changeset.change(is_active: not type.is_active)
        |> Repo.update()
    end
  end

  def toggle_department_type_active(_id), do: {:error, :not_found}

  @spec delete_department_type(pos_integer()) :: :ok | {:error, :not_found | :in_use}
  def delete_department_type(id) when is_integer(id) and id > 0 do
    case Repo.get(DepartmentType, id) do
      nil ->
        {:error, :not_found}

      type ->
        in_use? = Repo.exists?(from(d in Department, where: d.department_type_id == ^id))

        if in_use? do
          {:error, :in_use}
        else
          case Repo.delete(type) do
            {:ok, _} -> :ok
            {:error, _} -> {:error, :in_use}
          end
        end
    end
  end

  def delete_department_type(_id), do: {:error, :not_found}

  # ============================================================================
  # Company Departments
  # ============================================================================

  @spec list_departments(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [Department.t()]} | {:error, :company_not_found}
  def list_departments(%Scope{} = scope, company_id, opts \\ []) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        sort_by = Keyword.get(opts, :sort_by, :name)
        sort_dir = Keyword.get(opts, :sort_dir, :asc)

        query =
          from(d in Department,
            join: t in assoc(d, :type),
            where: d.company_id == ^company_id,
            preload: [type: t]
          )

        query =
          case sort_by do
            :category ->
              from([d, t] in query, order_by: [{^sort_dir, t.category}, {:asc, t.name}])

            :status ->
              from([d, t] in query, order_by: [{^sort_dir, d.status}, {:asc, t.name}])

            :code ->
              from([d, t] in query, order_by: [{^sort_dir, t.code}])

            _ ->
              from([d, t] in query, order_by: [{^sort_dir, t.name}])
          end

        {:ok, Repo.all(query)}
    end
  end

  @spec list_available_department_types(Scope.t(), pos_integer()) ::
          {:ok, [DepartmentType.t()]} | {:error, :company_not_found}
  def list_available_department_types(%Scope{} = scope, company_id) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        existing_type_ids =
          Repo.all(
            from(d in Department,
              where: d.company_id == ^company_id,
              select: d.department_type_id
            )
          )

        query =
          from(t in DepartmentType,
            where: t.is_active == true and t.id not in ^existing_type_ids,
            order_by: [asc: t.name]
          )

        {:ok, Repo.all(query)}
    end
  end

  @spec create_department(Scope.t(), pos_integer(), map()) ::
          {:ok, Department.t()} | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_department(%Scope{} = scope, company_id, attrs) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        %Department{company_id: company_id}
        |> Department.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, dept} -> {:ok, Repo.preload(dept, :type)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec update_department_status(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          {:ok, Department.t()} | {:error, :company_not_found | :not_found | Ecto.Changeset.t()}
  def update_department_status(%Scope{} = scope, company_id, department_id, status) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        query =
          from(d in Department,
            where: d.id == ^department_id and d.company_id == ^company_id,
            preload: [:type]
          )

        case Repo.one(query) do
          nil ->
            {:error, :not_found}

          dept ->
            dept
            |> Department.status_changeset(status)
            |> Repo.update()
        end
    end
  end

  @spec delete_department(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :company_not_found | :not_found}
  def delete_department(%Scope{} = scope, company_id, department_id) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        query =
          from(d in Department, where: d.id == ^department_id and d.company_id == ^company_id)

        case Repo.one(query) do
          nil ->
            {:error, :not_found}

          dept ->
            case Repo.delete(dept) do
              {:ok, _} -> :ok
              {:error, _} -> {:error, :not_found}
            end
        end
    end
  end

  # ============================================================================
  # Company Relationships
  # ============================================================================

  @spec list_relationships(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, :company_not_found}
  def list_relationships(%Scope{} = scope, company_id, _opts \\ []) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        outgoing =
          from(r in Relationship,
            join: rc in assoc(r, :related_company),
            join: t in assoc(r, :type),
            where: r.company_id == ^company_id and is_nil(r.deleted_at) and is_nil(rc.deleted_at),
            preload: [related_company: rc, type: t]
          )
          |> Repo.all()
          |> Enum.map(fn r ->
            %{
              id: r.id,
              direction: :outgoing,
              relationship: r,
              type: r.type,
              other_company: Summary.from_schema(r.related_company),
              effective_from: r.effective_from,
              effective_to: r.effective_to,
              is_active: Relationship.active?(r)
            }
          end)

        incoming =
          from(r in Relationship,
            join: c in assoc(r, :company),
            join: t in assoc(r, :type),
            where:
              r.related_company_id == ^company_id and is_nil(r.deleted_at) and
                is_nil(c.deleted_at),
            preload: [company: c, type: t]
          )
          |> Repo.all()
          |> Enum.map(fn r ->
            %{
              id: r.id,
              direction: :incoming,
              relationship: r,
              type: r.type,
              other_company: Summary.from_schema(r.company),
              effective_from: r.effective_from,
              effective_to: r.effective_to,
              is_active: Relationship.active?(r)
            }
          end)

        all_rels =
          (outgoing ++ incoming)
          |> Enum.sort_by(fn item -> {item.other_company.name, item.type.name} end)

        {:ok, all_rels}
    end
  end

  @spec list_available_related_companies(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_available_related_companies(%Scope{} = scope, company_id) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        companies =
          from(c in Tenancy.scope_query(Schema, scope),
            where: c.id != ^company_id and is_nil(c.deleted_at),
            order_by: c.name
          )
          |> Repo.all()
          |> Enum.map(&Summary.from_schema/1)

        {:ok, companies}
    end
  end

  @spec list_active_relationship_types() :: {:ok, [RelationshipType.t()]}
  def list_active_relationship_types do
    types =
      from(t in RelationshipType,
        where: t.is_active == true,
        order_by: t.name
      )
      |> Repo.all()

    {:ok, types}
  end

  @spec create_relationship(Scope.t(), pos_integer(), map()) ::
          {:ok, Relationship.t()}
          | {:error, :company_not_found | :related_company_not_found | Ecto.Changeset.t()}
  def create_relationship(%Scope{} = scope, company_id, attrs) do
    raw_related_id =
      Map.get(attrs, :related_company_id) || Map.get(attrs, "related_company_id")

    related_id =
      case raw_related_id do
        id when is_integer(id) ->
          id

        id when is_binary(id) ->
          case Integer.parse(id) do
            {parsed, ""} -> parsed
            _ -> nil
          end

        _ ->
          nil
      end

    with {:ok, _company} <- live_company(scope, company_id) do
      if related_id != nil do
        case live_company(scope, related_id) do
          {:ok, _related} ->
            %Relationship{company_id: company_id}
            |> Relationship.changeset(attrs)
            |> Repo.insert()
            |> case do
              {:ok, rel} -> {:ok, Repo.preload(rel, [:type, :related_company, :company])}
              {:error, changeset} -> {:error, changeset}
            end

          {:error, :company_not_found} ->
            {:error, :company_not_found}
        end
      else
        %Relationship{company_id: company_id}
        |> Relationship.changeset(attrs)
        |> Repo.insert()
      end
    end
  end

  @spec update_relationship(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Relationship.t()}
          | {:error, :company_not_found | :not_found | Ecto.Changeset.t()}
  def update_relationship(%Scope{} = scope, company_id, relationship_id, attrs) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        query =
          from(r in Relationship,
            where:
              r.id == ^relationship_id and
                (r.company_id == ^company_id or r.related_company_id == ^company_id) and
                is_nil(r.deleted_at),
            preload: [:type, :related_company, :company]
          )

        case Repo.one(query) do
          nil ->
            {:error, :not_found}

          rel ->
            rel
            |> Relationship.update_changeset(attrs)
            |> Repo.update()
        end
    end
  end

  @spec delete_relationship(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :company_not_found | :not_found}
  def delete_relationship(%Scope{} = scope, company_id, relationship_id) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        query =
          from(r in Relationship,
            where:
              r.id == ^relationship_id and
                (r.company_id == ^company_id or r.related_company_id == ^company_id) and
                is_nil(r.deleted_at)
          )

        case Repo.one(query) do
          nil ->
            {:error, :not_found}

          rel ->
            case Repo.update(Ecto.Changeset.change(rel, %{deleted_at: now()})) do
              {:ok, _} -> :ok
              {:error, _} -> {:error, :not_found}
            end
        end
    end
  end

  # ============================================================================
  # External Accesses
  # ============================================================================

  @spec list_company_accesses(Scope.t(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_company_accesses(%Scope{} = scope, company_id) do
    list_company_accesses(scope, company_id, :all)
  end

  @spec list_external_accesses(Scope.t(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_external_accesses(%Scope{} = scope, company_id) do
    list_company_accesses(scope, company_id, :all)
  end

  @spec list_company_accesses_for_user(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_company_accesses_for_user(%Scope{} = scope, company_id, user_id)
      when is_integer(user_id) and user_id > 0 do
    list_company_accesses(scope, company_id, user_id)
  end

  @spec list_external_accesses(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_external_accesses(%Scope{} = scope, company_id, user_id)
      when is_integer(user_id) and user_id > 0 do
    list_company_accesses(scope, company_id, user_id)
  end

  @doc """
  Lists active external accesses granting access TO scoped companies FOR a user.

  Returns accesses where the granted company is in scope and active, the access
  is active and not deleted, and the target user ID matches.

  Tenant isolation is preserved because the base query is scoped to companies
  owned by the caller's tenant. The user ID filter is an opaque foreign integer
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
          access.user_id == ^user_id and is_nil(access.deleted_at) and
            is_nil(company.deleted_at),
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
          {:ok, ExternalAccessSummary.t()}
          | {:error, access_lookup_error() | Ecto.Changeset.t()}
  def grant_external_access(%Scope{} = scope, company_id, access_id) do
    update_external_access(scope, company_id, access_id, %{
      is_active: true,
      access_granted_at: now()
    })
  end

  @spec revoke_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, access_lookup_error() | Ecto.Changeset.t()}
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
            relationship.id == ^relationship_id and
              relationship.company_id == ^company_id and
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

  defp filter_companies_by_search(query, nil), do: query

  defp filter_companies_by_search(query, search) do
    pattern = "%#{escape_like(search)}%"

    from(company in query,
      where:
        ilike(company.name, ^pattern) or ilike(company.code, ^pattern) or
          ilike(coalesce(company.legal_name, ""), ^pattern) or
          ilike(coalesce(company.email, ""), ^pattern) or
          ilike(coalesce(company.jurisdiction, ""), ^pattern)
    )
  end

  defp filter_companies_by_status(query, nil), do: query

  defp filter_companies_by_status(query, status) do
    from(company in query, where: company.status == ^status)
  end

  defp order_companies(query, sort_by, sort_dir) do
    case sort_by do
      :status ->
        from(company in query,
          order_by: [{^sort_dir, company.status}, {:asc, company.name}, {:asc, company.id}]
        )

      :jurisdiction ->
        from(company in query,
          order_by: [
            {^sort_dir, company.jurisdiction},
            {:asc, company.name},
            {:asc, company.id}
          ]
        )

      :name ->
        from(company in query,
          order_by: [{^sort_dir, company.name}, {:asc, company.id}]
        )
    end
  end

  defp with_company_index_context(query) do
    from(company in query,
      left_join: parent in Schema,
      on: parent.id == company.parent_id and is_nil(parent.deleted_at),
      left_join: primary in "tenant_primary_companies",
      on: primary.tenant_id == company.tenant_id and primary.company_id == company.id,
      select: %{
        company: company,
        parent_name: parent.name,
        is_primary: not is_nil(primary.company_id)
      }
    )
  end

  defp normalize_search(nil), do: nil

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_search(_value), do: nil

  defp normalize_company_status(value) when is_binary(value) do
    value = String.downcase(String.trim(value))

    if value in Schema.statuses(), do: value
  end

  defp normalize_company_status(_value), do: nil

  defp normalize_company_sort_by(value) when is_atom(value) and value in @company_sort_fields,
    do: value

  defp normalize_company_sort_by(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.trim()
    |> case do
      "status" -> :status
      "jurisdiction" -> :jurisdiction
      _ -> :name
    end
  end

  defp normalize_company_sort_by(_value), do: :name

  defp normalize_sort_dir(:desc), do: :desc

  defp normalize_sort_dir(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "desc" -> :desc
      _ -> :asc
    end
  end

  defp normalize_sort_dir(_value), do: :asc

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp normalize_company_page_size(value) do
    case positive_integer(value) do
      size when size in @company_page_sizes -> size
      _ -> 25
    end
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)

  defp escape_like(search) do
    search
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp now do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
