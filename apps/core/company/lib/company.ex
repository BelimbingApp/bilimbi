defmodule Bilimbi.Core.Company do
  @moduledoc """
  Public API for the required Company business Module.

  The first compatibility slice exposes explicit primary-company identity
  while keeping Ecto schemas and query details private to this Module.
  Reference types, departments, relationships, and external accesses keep
  their public names here and are implemented in the sibling modules.
  """

  import Ecto.Query

  require Logger

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.FieldPolicy
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError, as: TenantInvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError, as: TenantNotProvisionedError
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.AdministrationIndex
  alias Bilimbi.Core.Company.AdministrationPage
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.Departments
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.ExternalAccesses
  alias Bilimbi.Core.Company.ExternalAccessSummary
  alias Bilimbi.Core.Company.LegalEntityType
  alias Bilimbi.Core.Company.Lifecycle
  alias Bilimbi.Core.Company.LiveCompanyProof
  alias Bilimbi.Core.Company.PrimaryCompanyInvariantError
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.PrimaryCompanyNotProvisionedError
  alias Bilimbi.Core.Company.ReferenceTypes
  alias Bilimbi.Core.Company.Relationship
  alias Bilimbi.Core.Company.Relationships
  alias Bilimbi.Core.Company.RelationshipType
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary
  alias Bilimbi.Core.Company.TenantPrimaryCompany

  @type lookup_error :: :not_provisioned | :invariant_violation | :database_unavailable
  @type access_lookup_error :: :not_found | :company_not_found | :relationship_not_found
  @type lifecycle_operation :: Lifecycle.operation()
  @type lifecycle_error :: Lifecycle.error()
  @manage_across_tenant_capability "admin.company.tenant-wide.manage"

  @spec get_company(Scope.t(), pos_integer()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_company(%Scope{} = scope, company_id) when is_integer(company_id) and company_id > 0 do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      company -> {:ok, Summary.for_scope(company, scope)}
    end
  end

  def get_company(%Scope{}, _company_id), do: {:error, :not_found}

  @doc """
  The company fields the scope's actor may not see, in policy order.

  `tax_id` and `email` need `admin.company.sensitive.view`
  (`Bilimbi.Core.Company.Summary.field_policy/0`). Every summary this module
  returns already carries `Bilimbi.Base.Authz.Withheld` in those fields for
  such a reader; this names them for the update path and for the list
  search, which does not match a withheld column. The audit views withhold
  the same columns through the policy `Bilimbi.Core.Company.Contributions`
  declares for `auditable_types/0`.
  """
  @spec withheld_fields(Scope.t()) :: [atom()]
  def withheld_fields(%Scope{} = scope) do
    Authz.withheld_fields(scope, Summary.field_policy())
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
      |> Summary.for_scope(scope)

    {:ok, companies}
  end

  @doc """
  Dashboard counts and one live company, preferring the requested company ID.

  The fallback is the first live company by ID, as in `list_companies/1`.
  Counts cover all live companies in the tenant while only one company record
  is returned. The counts and selected company share one database snapshot.
  """
  @spec dashboard_summary(Scope.t(), pos_integer()) ::
          {:ok,
           %{total: non_neg_integer(), active: non_neg_integer(), company: Summary.t() | nil}}
  def dashboard_summary(%Scope{} = scope, preferred_company_id)
      when is_integer(preferred_company_id) and preferred_company_id > 0 do
    result =
      from(company in Tenancy.scope_query(Schema, scope),
        where: is_nil(company.deleted_at),
        windows: [all_companies: []],
        order_by: [desc: company.id == ^preferred_company_id, asc: company.id],
        limit: 1,
        select:
          {company, over(count(company.id), :all_companies),
           over(filter(count(company.id), company.status == "active"), :all_companies)}
      )
      |> Repo.one()

    case result do
      nil ->
        {:ok, %{total: 0, active: 0, company: nil}}

      {company, total, active} ->
        {:ok, %{total: total, active: active, company: Summary.for_scope(company, scope)}}
    end
  end

  @doc """
  Lists one bounded page of live companies for the administration index.

  Options: `:page`, `:page_size` (1..300), `:search` (name, code, legal
  name, email, jurisdiction), `:status_filter` (`:all` or one of
  `Schema.statuses/0`), `:sort_by` (`:name`, `:status`, or
  `:jurisdiction`), and `:sort_dir` (`:asc` or `:desc`). Each entry
  carries its parent company's name and whether it is the tenant's
  designated primary company.
  """
  @spec list_administration_page(Scope.t(), keyword()) ::
          {:ok, AdministrationPage.t()} | {:error, :invalid_options}
  def list_administration_page(%Scope{} = scope, options \\ []) do
    with {:ok, normalized_options} <- AdministrationIndex.normalize_options(options) do
      {:ok, AdministrationIndex.page(scope, normalized_options)}
    end
  end

  @doc """
  Lists the live companies an actor may target for an authorized operation.

  Pass the sealed `%Bilimbi.Base.Tenancy.Scope{}` for the person performing
  the work. That clause reads the actor the authentication edge sealed onto
  the scope through `Bilimbi.Base.Authz.scope_actor/1`. A system scope names
  nobody and returns `{:error, :unauthorized}`. The
  `%Bilimbi.Base.Authz.Actor{}` clause remains for a caller that already holds
  that actor; both forms return the same result for the same sealed user.

  The operation capability and company reach are independent: the tenant-wide
  capability expands the actor's reach but never authorizes an operation by
  itself. Every returned company remains inside the actor's validated tenant
  scope.
  """
  @spec list_selectable_companies(Actor.t() | Scope.t(), String.t()) ::
          {:ok, [Summary.t()]} | {:error, :unauthorized}
  def list_selectable_companies(%Scope{} = scope, operation_capability)
      when is_binary(operation_capability) do
    case Authz.scope_actor(scope) do
      {:ok, actor} -> list_selectable_companies(actor, operation_capability)
      {:error, :no_authenticated_actor} -> {:error, :unauthorized}
    end
  end

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

  Pass the sealed `%Bilimbi.Base.Tenancy.Scope{}` for the person performing
  the work. That clause reads the actor the authentication edge sealed onto
  the scope through `Bilimbi.Base.Authz.scope_actor/1`, then uses the same
  rules as the `%Bilimbi.Base.Authz.Actor{}` clause. A system scope names
  nobody: a positive company id is `{:error, :unauthorized}`, and a malformed
  id is `{:error, :not_found}`.

  Missing, deleted, and cross-tenant companies are indistinguishable. A
  sibling company additionally requires the explicit tenant-wide reach
  capability. The answer is the authorized company's id, not a summary: the
  caller is acting on the company, not reading it, so no field policy is
  evaluated.
  """
  @spec authorize_company_target(Actor.t() | Scope.t(), term(), String.t()) ::
          {:ok, pos_integer()} | {:error, :not_found | :unauthorized}
  def authorize_company_target(%Scope{} = scope, company_id, operation_capability)
      when is_binary(operation_capability) do
    case Authz.scope_actor(scope) do
      {:ok, actor} -> authorize_company_target(actor, company_id, operation_capability)
      {:error, :no_authenticated_actor} -> unauthorized_without_actor(company_id)
    end
  end

  def authorize_company_target(%Actor{} = actor, company_id, operation_capability)
      when is_integer(company_id) and company_id > 0 and is_binary(operation_capability) do
    with true <- capability_allowed?(actor, operation_capability),
         {:ok, company_id} <- require_live_company(actor.scope, company_id),
         true <-
           company_id == actor.company_id or
             capability_allowed?(actor, @manage_across_tenant_capability) do
      {:ok, company_id}
    else
      false -> {:error, :unauthorized}
      {:error, :not_found} = error -> error
    end
  end

  def authorize_company_target(%Actor{}, _company_id, operation_capability)
      when is_binary(operation_capability),
      do: {:error, :not_found}

  defp unauthorized_without_actor(company_id) when is_integer(company_id) and company_id > 0,
    do: {:error, :unauthorized}

  defp unauthorized_without_actor(_company_id), do: {:error, :not_found}

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

  @doc """
  Live company ids in this tenant, as a query a sibling may compose.

  This is the only company query another module may embed, and only as
  `where: other.company_id in subquery(live_company_ids_query(scope))`.
  It replaces loading every company row to throw the rows away. The query
  selects ids of companies that are not soft-deleted, the same set as
  `list_companies/1`.
  """
  @spec live_company_ids_query(Scope.t()) :: Ecto.Query.t()
  def live_company_ids_query(%Scope{} = scope) do
    from(company in Tenancy.scope_query(Schema, scope),
      where: is_nil(company.deleted_at),
      select: company.id
    )
  end

  @doc """
  Live company ids in this tenant, oldest id first.

  The same set as `list_companies/1` and `live_company_ids_query/1`, selected
  as ids. `list_tenant_company_ids/1` is the other id list and includes
  soft-deleted companies for the user listing; authorization must not use it.
  """
  @spec list_live_company_ids(Scope.t()) :: {:ok, [pos_integer()]}
  def list_live_company_ids(%Scope{} = scope) do
    ids =
      scope
      |> live_company_ids_query()
      |> order_by([company], asc: company.id)
      |> Repo.all()

    {:ok, ids}
  end

  @doc """
  Whether one company is live in this tenant.

  A missing, soft-deleted, or other-tenant id is false. The check is an
  existence query on `live_company_ids_query/1`, not a full company row.
  """
  @spec live_company?(Scope.t(), term()) :: boolean()
  def live_company?(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    scope
    |> live_company_ids_query()
    |> where([company], company.id == ^company_id)
    |> Repo.exists?()
  end

  def live_company?(%Scope{}, _company_id), do: false

  @doc """
  Confirms one company is live in this tenant, returning its id.

  For a caller that only needs the company to exist before it acts on
  something attached to it. It runs the one tenant-scoped existence query of
  `live_company?/2` and builds no summary, so it evaluates no field policy
  and writes no decision. A caller that shows the company to a reader uses
  `get_company/2`, which withholds what the reader may not see.
  """
  @spec require_live_company(Scope.t(), term()) :: {:ok, pos_integer()} | {:error, :not_found}
  def require_live_company(%Scope{} = scope, company_id) do
    if live_company?(scope, company_id), do: {:ok, company_id}, else: {:error, :not_found}
  end

  @doc """
  The display name of one live company in this tenant.

  The name a header or workspace strip shows: the legal name when there is
  one, otherwise the name, as `Summary.display_name/1` reads it. One
  tenant-scoped query selecting those two columns, so it evaluates no field
  policy and writes no decision. A caller that needs any other fact of the
  company uses `get_company/2`.
  """
  @spec display_name(Scope.t(), term()) :: {:ok, String.t()} | {:error, :not_found}
  def display_name(%Scope{} = scope, company_id) when is_integer(company_id) and company_id > 0 do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at),
        select: %{legal_name: company.legal_name, name: company.name}
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      names -> {:ok, Summary.display_name(names)}
    end
  end

  def display_name(%Scope{}, _company_id), do: {:error, :not_found}

  @doc """
  The columns the administration search matches for this scope's actor, in
  match order. A sensitive column the actor may not see is not matched.
  """
  @spec searchable_columns(Scope.t()) :: [atom()]
  def searchable_columns(%Scope{} = scope), do: AdministrationIndex.searchable_columns(scope)

  @doc """
  Names of the given live companies in this tenant.

  Missing, soft-deleted, and other-tenant ids are omitted. The value is
  `companies.name`, the same field `get_company/2` exposes as `Summary.name`.
  An empty id list does not touch the database.
  """
  @spec live_company_names(Scope.t(), [pos_integer()]) :: %{pos_integer() => String.t()}
  def live_company_names(%Scope{} = scope, company_ids) when is_list(company_ids) do
    company_ids = for id <- company_ids, is_integer(id) and id > 0, uniq: true, do: id

    if company_ids == [] do
      %{}
    else
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id in ^company_ids and is_nil(company.deleted_at),
        select: {company.id, company.name}
      )
      |> Repo.all()
      |> Map.new()
    end
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

  @doc """
  Every `auditable_type` a company's audit rows are recorded under.

  Capture records the schema's module name; the others are the name a row
  adopted from Belimbing carries. The record history reads all of them, and
  `Bilimbi.Core.Company.Contributions` declares the company field policy
  against each, so the audit views withhold the same columns as the page.
  """
  @spec auditable_types() :: [String.t()]
  def auditable_types do
    ["Bilimbi.Core.Company.Schema", "Bilimbi.Core.Company", addressable_identity()]
  end

  @doc "Whether a department belongs to the requested tenant-owned company."
  @spec department_belongs_to_company?(Scope.t(), pos_integer(), pos_integer()) :: boolean()
  def department_belongs_to_company?(%Scope{} = scope, company_id, department_id)
      when is_integer(department_id) and department_id > 0 do
    case require_live_company(scope, company_id) do
      {:ok, _company_id} ->
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
                Summary.for_scope(company, scope)

              {:error, reason} ->
                Repo.rollback(reason)
            end
          else
            Summary.for_scope(company, scope)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> unwrap_mutation()
  end

  @doc """
  Updates a live Company record scoped to the caller's tenant.

  `status` is not an attribute this path writes. A status change is one of
  the lifecycle operations below (`archive_company/3`, `suspend_company/3`,
  `activate_company/3`, `reactivate_company/3`); an attribute map that
  carries `status` is refused with a changeset error on that field rather
  than silently dropped.

  A field the scope's actor may not see (`withheld_fields/1`) is not theirs
  to set either: attributes that name one are refused with an error on that
  field, and nothing is written. The refusal is the same whatever value is
  sent, the stored one included, so a caller cannot confirm a guess.
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
        |> FieldPolicy.refuse_attempts(withheld_fields(scope), attributes)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, Summary.for_scope(updated, scope)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def update_company(%Scope{}, _company_id, _attributes), do: {:error, :not_found}

  # Lifecycle. The public names stay here; the transition table and the
  # bodies live in `Lifecycle`.

  @doc """
  Archives a live company: `pending`, `active` or `suspended` to `archived`.

  Archived is final; no operation leaves it. Every lifecycle operation takes
  the sealed scope of the person performing it, requires
  `admin.company.update` on it now and, for a company other than the one the
  person signed in under, `admin.company.tenant-wide.manage` as well (as
  `authorize_company_target/3` decides), accepts an optional `reason:` (trimmed,
  at most `Lifecycle.reason_max_length/0` characters; blank records none),
  writes the status and one retained `company.<event>` audit action in the
  same transaction, and returns the updated summary. A system scope
  is `{:error, :forbidden}`; a company the operation does not
  start from is `{:error, {:invalid_transition, current_status}}`; a missing,
  deleted or cross-tenant id is `{:error, :not_found}`; a reason longer than
  that limit is `{:error, :reason_too_long}` and one that is not text is
  `{:error, :invalid_reason}`. `archive_company/3` and `suspend_company/3`
  refuse the tenant's primary company with `{:error, :primary_company}` and
  the performing account's own signed-in company with `{:error, :own_company}`.
  The table of operations is `docs/README.md` "Lifecycle".
  """
  @spec archive_company(Scope.t(), pos_integer(), keyword()) ::
          {:ok, Summary.t()} | {:error, lifecycle_error()}
  def archive_company(%Scope{} = scope, company_id, opts \\ []),
    do: Lifecycle.apply(:archive, scope, company_id, opts)

  @doc "Suspends an `active` company. See `archive_company/3` for the shared contract."
  @spec suspend_company(Scope.t(), pos_integer(), keyword()) ::
          {:ok, Summary.t()} | {:error, lifecycle_error()}
  def suspend_company(%Scope{} = scope, company_id, opts \\ []),
    do: Lifecycle.apply(:suspend, scope, company_id, opts)

  @doc "Activates a `pending` company. See `archive_company/3` for the shared contract."
  @spec activate_company(Scope.t(), pos_integer(), keyword()) ::
          {:ok, Summary.t()} | {:error, lifecycle_error()}
  def activate_company(%Scope{} = scope, company_id, opts \\ []),
    do: Lifecycle.apply(:activate, scope, company_id, opts)

  @doc "Reactivates a `suspended` company. See `archive_company/3` for the shared contract."
  @spec reactivate_company(Scope.t(), pos_integer(), keyword()) ::
          {:ok, Summary.t()} | {:error, lifecycle_error()}
  def reactivate_company(%Scope{} = scope, company_id, opts \\ []),
    do: Lifecycle.apply(:reactivate, scope, company_id, opts)

  @doc """
  The lifecycle operations a company in `status` may undergo.

  A page offers exactly these controls and nothing else; `archived` yields
  `[]`. The order is fixed: activate, reactivate, suspend, archive.
  """
  @spec lifecycle_operations(String.t()) :: [lifecycle_operation()]
  defdelegate lifecycle_operations(status), to: Lifecycle, as: :operations_from

  @doc """
  The statuses a company may be created in: `active` (the default) and
  `pending`. `suspended` and `archived` are reached only through the
  lifecycle operations.
  """
  @spec initial_statuses() :: [String.t()]
  defdelegate initial_statuses(), to: Schema

  @doc "The longest reason a lifecycle operation records, in characters."
  @spec lifecycle_reason_max_length() :: pos_integer()
  defdelegate lifecycle_reason_max_length(), to: Lifecycle, as: :reason_max_length

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
      |> Summary.for_scope(scope)

    {:ok, companies}
  end

  def list_child_companies(%Scope{}, _company_id), do: {:ok, []}

  @doc """
  Returns whether the company is designated as the primary company for the scope's tenant.
  """
  @spec primary_company?(Scope.t(), pos_integer()) :: boolean()
  def primary_company?(%Scope{} = scope, company_id)
      when is_integer(company_id) and company_id > 0 do
    Tenancy.scope_query(TenantPrimaryCompany, scope)
    |> where([primary], primary.company_id == ^company_id)
    |> Repo.exists?()
  end

  def primary_company?(%Scope{}, _company_id), do: false

  # Reference types. The public names stay here; the bodies live in `ReferenceTypes`.

  @spec list_legal_entity_types(keyword()) :: {:ok, [LegalEntityType.t()]}
  defdelegate list_legal_entity_types(opts \\ []), to: ReferenceTypes

  @spec get_legal_entity_type(pos_integer()) :: {:ok, LegalEntityType.t()} | {:error, :not_found}
  defdelegate get_legal_entity_type(id), to: ReferenceTypes

  @doc """
  Creates a legal entity type.

  Requires `admin.company.create` on the sealed scope now. The type screen's
  `can_create?` assign only shows the control. An anonymous system actor
  (seeds, `Tenancy.scope/1`) is allowed; a person is decided by Authz.
  """
  @spec create_legal_entity_type(Scope.t(), map()) ::
          {:ok, LegalEntityType.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  defdelegate create_legal_entity_type(scope, attrs), to: ReferenceTypes

  @doc """
  Updates a legal entity type.

  Requires `admin.company.update` on the sealed scope now.
  """
  @spec update_legal_entity_type(Scope.t(), pos_integer() | LegalEntityType.t(), map()) ::
          {:ok, LegalEntityType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  defdelegate update_legal_entity_type(scope, type_or_id, attrs), to: ReferenceTypes

  @spec toggle_legal_entity_type_active(Scope.t(), pos_integer()) ::
          {:ok, LegalEntityType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  defdelegate toggle_legal_entity_type_active(scope, id), to: ReferenceTypes

  @spec delete_legal_entity_type(Scope.t(), pos_integer()) ::
          :ok | {:error, :forbidden | :not_found | :in_use}
  defdelegate delete_legal_entity_type(scope, id), to: ReferenceTypes

  @spec list_department_types(keyword()) :: {:ok, [DepartmentType.t()]}
  defdelegate list_department_types(opts \\ []), to: ReferenceTypes

  @spec get_department_type(pos_integer()) :: {:ok, DepartmentType.t()} | {:error, :not_found}
  defdelegate get_department_type(id), to: ReferenceTypes

  @doc """
  Creates a department type.

  Requires `admin.company.create` on the sealed scope now. The type screen's
  `can_create?` assign only shows the control. An anonymous system actor
  (seeds, `Tenancy.scope/1`) is allowed; a person is decided by Authz.
  """
  @spec create_department_type(Scope.t(), map()) ::
          {:ok, DepartmentType.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  defdelegate create_department_type(scope, attrs), to: ReferenceTypes

  @doc """
  Updates a department type.

  Requires `admin.company.update` on the sealed scope now.
  """
  @spec update_department_type(Scope.t(), pos_integer() | DepartmentType.t(), map()) ::
          {:ok, DepartmentType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  defdelegate update_department_type(scope, type_or_id, attrs), to: ReferenceTypes

  @spec toggle_department_type_active(Scope.t(), pos_integer()) ::
          {:ok, DepartmentType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  defdelegate toggle_department_type_active(scope, id), to: ReferenceTypes

  @spec delete_department_type(Scope.t(), pos_integer()) ::
          :ok | {:error, :forbidden | :not_found | :in_use}
  defdelegate delete_department_type(scope, id), to: ReferenceTypes

  # Departments. The public names stay here; the bodies live in `Departments`.

  @spec list_departments(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [Department.t()]} | {:error, :company_not_found}
  defdelegate list_departments(scope, company_id, opts \\ []), to: Departments

  @spec list_available_department_types(Scope.t(), pos_integer()) ::
          {:ok, [DepartmentType.t()]} | {:error, :company_not_found}
  defdelegate list_available_department_types(scope, company_id), to: Departments

  @spec create_department(Scope.t(), pos_integer(), map()) ::
          {:ok, Department.t()} | {:error, :company_not_found | Ecto.Changeset.t()}
  defdelegate create_department(scope, company_id, attrs), to: Departments

  @spec update_department_status(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          {:ok, Department.t()} | {:error, :company_not_found | :not_found | Ecto.Changeset.t()}
  defdelegate update_department_status(scope, company_id, department_id, status), to: Departments

  @doc """
  Appoints (or clears, with `head_id: nil`) the head of an existing department.

  The head is an employee id, which this module does not resolve — a caller that
  can name employees (a Core module that depends on `core/company`) supplies it.
  The department must belong to `company_id`.
  """
  @spec update_department_head(Scope.t(), pos_integer(), pos_integer(), pos_integer() | nil) ::
          {:ok, Department.t()} | {:error, :company_not_found | :not_found | Ecto.Changeset.t()}
  defdelegate update_department_head(scope, company_id, department_id, head_id), to: Departments

  @spec delete_department(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :company_not_found | :not_found}
  defdelegate delete_department(scope, company_id, department_id), to: Departments

  # Relationships. The public names stay here; the bodies live in `Relationships`.

  @spec list_relationships(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, :company_not_found}
  defdelegate list_relationships(scope, company_id, opts \\ []), to: Relationships

  @spec list_available_related_companies(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  defdelegate list_available_related_companies(scope, company_id), to: Relationships

  @spec list_active_relationship_types() :: {:ok, [RelationshipType.t()]}
  defdelegate list_active_relationship_types(), to: Relationships

  @spec create_relationship(Scope.t(), pos_integer(), map()) ::
          {:ok, Relationship.t()}
          | {:error,
             :forbidden | :company_not_found | :related_company_not_found | Ecto.Changeset.t()}
  defdelegate create_relationship(scope, company_id, attrs), to: Relationships

  @spec update_relationship(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Relationship.t()}
          | {:error, :forbidden | :company_not_found | :not_found | Ecto.Changeset.t()}
  defdelegate update_relationship(scope, company_id, relationship_id, attrs), to: Relationships

  @spec delete_relationship(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :forbidden | :company_not_found | :not_found}
  defdelegate delete_relationship(scope, company_id, relationship_id), to: Relationships

  # External accesses. The public names stay here; the bodies live in `ExternalAccesses`.

  @spec list_external_accesses(Scope.t(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  defdelegate list_external_accesses(scope, company_id), to: ExternalAccesses

  @spec list_external_accesses(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  defdelegate list_external_accesses(scope, company_id, user_id), to: ExternalAccesses

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
  defdelegate list_external_accesses_for_user(scope, user_id), to: ExternalAccesses

  @spec get_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()} | {:error, access_lookup_error()}
  defdelegate get_external_access(scope, company_id, access_id), to: ExternalAccesses

  @spec create_external_access(Scope.t(), pos_integer(), map()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, :company_not_found | :relationship_not_found | Ecto.Changeset.t()}
  defdelegate create_external_access(scope, company_id, attributes), to: ExternalAccesses

  @spec update_external_access(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, access_lookup_error() | Ecto.Changeset.t()}
  defdelegate update_external_access(scope, company_id, access_id, attributes),
    to: ExternalAccesses

  @spec grant_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, access_lookup_error() | Ecto.Changeset.t()}
  defdelegate grant_external_access(scope, company_id, access_id), to: ExternalAccesses

  @spec revoke_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, ExternalAccessSummary.t()}
          | {:error, access_lookup_error() | Ecto.Changeset.t()}
  defdelegate revoke_external_access(scope, company_id, access_id), to: ExternalAccesses

  @spec delete_external_access(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, access_lookup_error() | Ecto.Changeset.t()}
  defdelegate delete_external_access(scope, company_id, access_id), to: ExternalAccesses

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

  defp unwrap_mutation({:ok, result}), do: {:ok, result}
  defp unwrap_mutation({:error, reason}), do: {:error, reason}
end
