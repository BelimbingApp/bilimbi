defmodule Bilimbi.Core.Employee do
  @moduledoc """
  Deprecated compatibility API for tenant-scoped legacy HR records.

  New contacts and affiliations use Bilimbi.Core.Person. Existing HR columns
  and durable Employee IDs remain intact until People claims them; see docs/README.md.

  Employee identity remains separate from authentication identity. Every
  operation runs under a `Bilimbi.Base.Tenancy.Scope`, so the tenant is proven
  once at the edge. Ecto schemas stay private to this deep module.

  The platform orchestrator is the durable pair
  `(platform-operator primary company, employee_number \"SYS-001\")` with
  `employee_type \"agent\"`. Numeric employee IDs have no runtime meaning.
  Ordinary create/update/delete paths may not reserve, rewrite, adopt, or
  remove that identity; primary-company transfer must rehome the existing
  orchestrator explicitly rather than allowing a second one.
  """

  import Ecto.Query

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Database.WriteCapture
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee.AdministrationIndex
  alias Bilimbi.Core.Employee.AdministrationPage
  alias Bilimbi.Core.Employee.AffiliationLock
  alias Bilimbi.Core.Employee.AffiliationProof
  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.EmploymentOwner
  alias Bilimbi.Core.Employee.HrHandoffEntry
  alias Bilimbi.Core.Employee.HrHandoffPage
  alias Bilimbi.Core.Employee.Schema
  alias Bilimbi.Core.Employee.Summary
  alias Bilimbi.Core.Employee.TypeAdministrationIndex
  alias Bilimbi.Core.Employee.TypeAdministrationPage
  alias Bilimbi.Core.Employee.TypeSummary
  alias Bilimbi.Core.Person
  alias Ecto.Changeset

  @system_types [
    %{code: "full_time", label: "Full Time"},
    %{code: "part_time", label: "Part Time"},
    %{code: "contractor", label: "Contractor"},
    %{code: "intern", label: "Intern"},
    %{code: "agent", label: "Agent"}
  ]
  @system_type_codes Enum.map(@system_types, & &1.code)
  @platform_orchestrator_number "SYS-001"
  @platform_orchestrator_type "agent"
  @platform_orchestrator_attributes %{
    employee_number: @platform_orchestrator_number,
    full_name: "Lara Bilimbi",
    short_name: "Lara",
    designation: "System Assistant",
    job_description:
      "Bilimbi's platform orchestrator. Guides setup and delegates bounded work to specialised agents.",
    employee_type: @platform_orchestrator_type,
    status: "active"
  }
  @protected_orchestrator_fields [:employee_number, :employee_type]
  @person_fact_fields [
    full_name: :full_name,
    designation: :title,
    email: :email,
    mobile_number: :phone,
    employment_start: :started_on,
    employment_end: :ended_on
  ]

  @identity_batch_limit 1_000
  @handoff_page_size 500
  @employee_read_capability "admin.employee.list"

  @doc "Resolves the Core Person/affiliation mapping without exposing either module's private schemas."
  def person_identity(%Scope{} = scope, employee_id) do
    with {:ok, employees} <- get_tenant_employees(scope, [employee_id]),
         true <- Map.has_key?(employees, employee_id),
         {:ok, affiliation} <- Person.legacy_affiliation(scope, employee_id) do
      {:ok,
       %{
         legacy_employee_id: affiliation.legacy_employee_id,
         person_id: affiliation.person_id,
         affiliation_id: affiliation.id,
         company_id: affiliation.company_id
       }}
    else
      false -> {:error, :employee_not_found}
      error -> error
    end
  end

  @doc """
  Resolves the Core Person mapping of up to 1,000 legacy employees at once.

  Returns `%{employee_id => %{person_id:, affiliation_id:, company_id:}}`,
  where `company_id` is the affiliation's company. Employees outside the
  scope's tenant and rows with no mapping yet are omitted. Visibility is the
  tenant's, archived companies included, like `get_tenant_employees/2`.

  The values are IDs only and reveal no identity or contact fact, so the
  read asks the employee read capability (`admin.employee.list`), not the
  contact view `person_identity/2` requires. An anonymous system actor
  passes. A list that is not of positive integers or holds more than 1,000
  distinct IDs is `:invalid_options`. The query count does not grow with the batch.
  """
  @spec person_identities(Scope.t(), [pos_integer()]) ::
          {:ok,
           %{
             pos_integer() => %{
               person_id: pos_integer(),
               affiliation_id: pos_integer(),
               company_id: pos_integer()
             }
           }}
          | {:error, :forbidden | :invalid_options}
  def person_identities(%Scope{} = scope, employee_ids) do
    with :ok <- authorize(scope, @employee_read_capability),
         {:ok, employee_ids} <- identity_batch(employee_ids) do
      {:ok, Person.legacy_mappings(scope, tenant_employee_ids(scope, employee_ids))}
    end
  end

  @doc """
  Reads one page of every retained legacy HR row in the scope's tenant, for
  the owner of employment facts to claim.

  Unlike `list_employees/2`, the read is tenant-wide and includes the rows
  of archived companies, agents and the platform orchestrator. It writes
  nothing and is ordered by ascending employee ID. Pass `nil` to start and
  the returned `next_cursor` to continue until it is `nil`. Each entry
  carries the HR facts, metadata, created/updated clocks and the Core Person
  mapping (`nil` IDs for a row that has none yet).

  IDs only grow, so a row created while paging appears on a later page; a
  row changed after its page was read is not delivered again. Register the
  owner (`register_employment_owner/1`) before paging so writes that start
  afterwards reach it through its callback. A write already in flight at
  registration may not, so page again after a grace period longer than any
  Core HR transaction (for example 60 seconds), comparing `updated_at`.

  Asks `admin.employee.list` (an anonymous system actor passes). Option
  `:limit` sets the page size, default 500, at most 1,000. A cursor that is
  not `nil` or a positive integer, or a bad limit, is `:invalid_options`.
  """
  @spec hr_handoff_page(Scope.t(), pos_integer() | nil, keyword()) ::
          {:ok, HrHandoffPage.t()} | {:error, :forbidden | :invalid_options}
  def hr_handoff_page(%Scope{} = scope, cursor, options \\ []) do
    with :ok <- authorize(scope, @employee_read_capability),
         {:ok, cursor} <- handoff_cursor(cursor),
         {:ok, limit} <- handoff_limit(options) do
      {:ok, company_ids} = Company.list_tenant_company_ids(scope)

      rows =
        from(employee in Schema,
          where: employee.company_id in ^company_ids and employee.id > ^cursor,
          order_by: [asc: employee.id],
          limit: ^(limit + 1)
        )
        |> Repo.all()

      {page, rest} = Enum.split(rows, limit)
      mappings = Person.legacy_mappings(scope, Enum.map(page, & &1.id))

      {:ok,
       %HrHandoffPage{
         entries: Enum.map(page, &HrHandoffEntry.from_schema(&1, Map.get(mappings, &1.id))),
         next_cursor: if(rest == [], do: nil, else: List.last(page).id)
       }}
    end
  end

  @doc """
  Registers the mounted owner of employment facts, from its application start.

  The module implements `Bilimbi.Core.Employee.EmploymentOwner`, whose
  moduledoc owns the contract. One owner at a time: registering the same
  module again is `:ok`, another is `:already_registered`, and a module
  without the callbacks is `:invalid_owner`. With none registered Core's
  writes call nothing. A write already in flight at registration may not call
  the owner, so the owner adopts existing rows with `hr_handoff_page/3` after
  registering, and again after a grace period.
  """
  @spec register_employment_owner(module()) ::
          :ok | {:error, :invalid_owner | :already_registered}
  def register_employment_owner(module), do: EmploymentOwner.register(module)

  @doc "Removes the employment owner when its application stops; another module is left registered."
  @spec unregister_employment_owner(module()) :: :ok
  def unregister_employment_owner(module), do: EmploymentOwner.unregister(module)

  @doc "The registered owner of employment facts, or `nil` when none is mounted."
  @spec employment_owner() :: module() | nil
  def employment_owner, do: EmploymentOwner.registered()

  @doc """
  Who owns one employee's employment facts, for Core's pages to say so.

  `nil` when no owner is registered; otherwise the owner's name and its page
  for this employee (`nil` when it offers none). Pass `nil` IDs for a page
  that shows no one employee, such as the list.
  """
  @spec employment_ownership(Scope.t(), pos_integer() | nil, pos_integer() | nil) ::
          %{name: String.t(), path: String.t() | nil} | nil
  def employment_ownership(%Scope{} = scope, company_id, employee_id) do
    case EmploymentOwner.registered() do
      nil -> nil
      owner -> EmploymentOwner.ownership(owner, scope, company_id, employee_id)
    end
  end

  @type lookup_error ::
          :company_not_found
          | :company_archived
          | :employee_not_found
          | :not_provisioned
          | :invariant_violation
          | :database_unavailable

  @type provision_status :: :created | :existing

  @doc """
  Returns one bounded, deterministic administration page for a live company.

  Options are a plain keyword list. Supported values are `:page`, `:page_size`,
  `:search`, `:type_filter` (`:all`, `:human`, or `:agent`), `:sort_by`
  (`:full_name`, `:employee_type_label`, or `:status`), and `:sort_dir`
  (`:asc` or `:desc`). The source `company_name` sort is intentionally absent:
  this API admits exactly one validated company, so it would be constant and a
  Company-table join would not be truthful or useful here.
  """
  @spec list_administration_page(Scope.t(), pos_integer(), keyword()) ::
          {:ok, AdministrationPage.t()} | {:error, :company_not_found | :invalid_options}
  def list_administration_page(scope, company_id, options \\ [])

  def list_administration_page(%Scope{} = scope, company_id, options)
      when is_integer(company_id) and company_id > 0 do
    with {:ok, normalized_options} <- AdministrationIndex.normalize_options(options),
         {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)) do
      {:ok, AdministrationIndex.page(company_id, normalized_options)}
    end
  end

  def list_administration_page(%Scope{}, _company_id, _options), do: {:error, :company_not_found}

  @spec list_employees(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_employees(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)) do
      {:ok, list_company_summaries(company_id)}
    end
  end

  @spec get_employee(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, lookup_error()}
  def get_employee(%Scope{} = scope, company_id, employee_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)),
         %Schema{} = employee <- employee_schema(company_id, employee_id) do
      {:ok, Summary.from_schema(employee)}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc """
  Resolves an employee through any live company visible to the tenant scope.

  The company check is `Company.live_company_ids_query/1` inside this
  statement. Do not load `Company.list_companies/1` and filter the ids in
  memory: that reads every company row in the tenant for one employee.
  """
  @spec get_employee(Scope.t(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :employee_not_found}
  def get_employee(%Scope{} = scope, employee_id) do
    case Repo.one(
           from(employee in Schema,
             where:
               employee.id == ^employee_id and
                 employee.company_id in subquery(Company.live_company_ids_query(scope))
           )
         ) do
      nil -> {:error, :employee_not_found}
      employee -> {:ok, Summary.from_schema(employee)}
    end
  end

  @doc """
  Full names of the given employees whose company is still live in the tenant.

  Same visibility as `get_employee/2`: an employee of a soft-deleted or
  other-tenant company is omitted. An empty id list does not touch the database.
  """
  @spec live_full_names(Scope.t(), [pos_integer()]) :: %{pos_integer() => String.t()}
  def live_full_names(%Scope{} = scope, employee_ids) when is_list(employee_ids) do
    employee_ids = for id <- employee_ids, is_integer(id) and id > 0, uniq: true, do: id

    if employee_ids == [] do
      %{}
    else
      from(employee in Schema,
        where:
          employee.id in ^employee_ids and
            employee.company_id in subquery(Company.live_company_ids_query(scope)),
        select: {employee.id, employee.full_name}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  @doc """
  Reads multiple employees by ID under the scope's tenant-wide visibility.

  Returns `{:ok, map}` keyed by employee ID. Non-existent IDs and employees
  outside the tenant are omitted rather than reported — the caller keeps its row
  and shows the durable id (ADR 0011).

  Scoped through `Company.list_tenant_company_ids/1`, which **includes
  soft-deleted companies**, deliberately and for the same reason
  `Core.User.get_tenant_users/2` does: a durable grant to an employee survives
  their company being archived, and an operator looking at that grant needs to
  know whose it is in order to revoke it. Archiving a company does not unmake
  the grant, so it must not hide the name.

  That differs from `get_employee/2`, which keeps an employee only when the
  company is still live (`Company.live_company_ids_query/1`). The difference
  is intended: that function answers
  "may this actor work with this employee", this one answers "who is this
  principal a grant already names".
  """
  @spec get_tenant_employees(Scope.t(), [pos_integer()]) ::
          {:ok, %{pos_integer() => Summary.t()}}
  def get_tenant_employees(%Scope{} = scope, employee_ids) when is_list(employee_ids) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    case company_ids do
      [] ->
        {:ok, %{}}

      ids ->
        employees =
          from(employee in Schema,
            where: employee.id in ^employee_ids and employee.company_id in ^ids
          )
          |> Repo.all()
          |> Enum.map(&Summary.from_schema/1)
          |> Map.new(&{&1.id, &1})

        {:ok, employees}
    end
  end

  @doc "Lists direct subordinates assigned to a supervisor in the given company."
  @spec list_subordinates(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, lookup_error()}
  def list_subordinates(%Scope{} = scope, company_id, supervisor_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)),
         %Schema{} = _supervisor <- employee_schema(company_id, supervisor_id) do
      subordinates =
        from(employee in Schema,
          where: employee.company_id == ^company_id and employee.supervisor_id == ^supervisor_id,
          order_by: [asc: employee.full_name, asc: employee.id]
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, subordinates}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc "Lists eligible employees to become direct subordinates of a supervisor in the company."
  @spec list_available_subordinates(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, lookup_error()}
  def list_available_subordinates(%Scope{} = scope, company_id, supervisor_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)),
         %Schema{} = _supervisor <- employee_schema(company_id, supervisor_id) do
      employees =
        from(employee in Schema,
          where:
            employee.company_id == ^company_id and
              employee.id != ^supervisor_id and
              (is_nil(employee.supervisor_id) or employee.supervisor_id != ^supervisor_id),
          order_by: [asc: employee.full_name, asc: employee.id]
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, employees}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc """
  One company read, partitioned for a supervisor's page.

  Proves the company and the supervisor once. `employees` is that company's
  list (the supervisor options). `subordinates` report to this employee.
  `available` are the other employees. `list_subordinates/3` and
  `list_available_subordinates/3` stay for callers that want one side only.
  """
  @spec supervision_lists(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok,
           %{
             employees: [Summary.t()],
             subordinates: [Summary.t()],
             available: [Summary.t()]
           }}
          | {:error, lookup_error()}
  def supervision_lists(%Scope{} = scope, company_id, employee_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)),
         %Schema{} = _supervisor <- employee_schema(company_id, employee_id) do
      employees = list_company_summaries(company_id)

      subordinates =
        employees
        |> Enum.filter(&(&1.supervisor_id == employee_id))
        |> Enum.sort_by(&{String.downcase(&1.full_name), &1.id})

      available =
        employees
        |> Enum.filter(&(&1.id != employee_id and &1.supervisor_id != employee_id))
        |> Enum.sort_by(&{String.downcase(&1.full_name), &1.id})

      {:ok, %{employees: employees, subordinates: subordinates, available: available}}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc "Assigns an employee as direct subordinate to a supervisor."
  @spec assign_subordinate(Scope.t(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | Changeset.t()}
  def assign_subordinate(%Scope{} = scope, company_id, supervisor_id, subordinate_id) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)),
         %Schema{} = _supervisor <- employee_schema(company_id, supervisor_id),
         %Schema{} = subordinate <- employee_schema(company_id, subordinate_id) do
      if subordinate.id == supervisor_id do
        {:error, :invariant_violation}
      else
        subordinate
        |> Schema.update_changeset(%{supervisor_id: supervisor_id})
        |> protect_platform_orchestrator_identity(subordinate)
        |> reject_reserved_orchestrator_number(subordinate)
        |> validate_references(scope, company_id, subordinate.id)
        |> persist_update(scope)
      end
    else
      {:error, reason} = error when reason in [:company_not_found, :company_archived] -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc "Removes subordinate relationship by clearing supervisor_id."
  @spec remove_subordinate(Scope.t(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | Changeset.t()}
  def remove_subordinate(%Scope{} = scope, company_id, supervisor_id, subordinate_id) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)),
         %Schema{} = _supervisor <- employee_schema(company_id, supervisor_id),
         %Schema{} = subordinate <- employee_schema(company_id, subordinate_id) do
      if subordinate.supervisor_id == supervisor_id do
        subordinate
        |> Schema.update_changeset(%{supervisor_id: nil})
        |> protect_platform_orchestrator_identity(subordinate)
        |> reject_reserved_orchestrator_number(subordinate)
        |> validate_references(scope, company_id, subordinate.id)
        |> persist_update(scope)
      else
        {:ok, Summary.from_schema(subordinate)}
      end
    else
      {:error, reason} = error when reason in [:company_not_found, :company_archived] -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc """
  Locks and proves one employee's affiliation with a live scoped company.

  The caller must already be inside the shared Repo transaction. The returned
  proof is valid only for that transaction and contains no Employee schema or
  queryable. Callers that also lock another module's rows keep the order on
  `Bilimbi.Core.Company.lock_writable_company/2`.

  Missing, cross-tenant, and company-mismatched identities all fail as
  `:not_found`; an archived company is `:company_archived`, since the lock is
  taken to write. `:invariant_violation` is reserved for the protected platform
  orchestrator, which is not available through this generic sibling-workflow
  seam.
  """
  @spec lock_affiliation(Scope.t(), term(), term()) ::
          {:ok, AffiliationProof.t()}
          | {:error,
             :invariant_violation | :not_found | :company_archived | :transaction_required}
  def lock_affiliation(%Scope{} = scope, company_id, employee_id) do
    AffiliationLock.lock(scope, company_id, employee_id)
  end

  @spec create_employee(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :company_not_found | :company_archived | Changeset.t()}
  def create_employee(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)) do
      scope |> creation_changeset(company_id, attributes) |> persist_insert(scope)
    end
  end

  @doc "Validates the same employment fields and references as create, without writing."
  @spec preview_create_employee(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, term()}
  def preview_create_employee(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)) do
      scope
      |> creation_changeset(company_id, attributes)
      |> Changeset.unsafe_validate_unique([:company_id, :employee_number], Repo)
      |> Changeset.apply_action(:insert)
      |> case do
        {:ok, employee} -> {:ok, Summary.from_schema(employee)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp creation_changeset(scope, company_id, attributes) do
    company_id
    |> Schema.creation_changeset(attributes)
    |> reject_reserved_orchestrator_number()
    |> validate_references(scope, company_id, nil)
  end

  @spec update_employee(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | Changeset.t()}
  def update_employee(%Scope{} = scope, company_id, employee_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)),
         %Schema{} = employee <- employee_schema(company_id, employee_id) do
      employee
      |> Schema.update_changeset(attributes)
      |> protect_platform_orchestrator_identity(employee)
      |> reject_reserved_orchestrator_number(employee)
      |> validate_references(scope, company_id, employee_id)
      |> persist_update(scope)
    else
      {:error, reason} = error when reason in [:company_not_found, :company_archived] -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @spec delete_employee(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, lookup_error() | :forbidden}
  def delete_employee(%Scope{} = scope, company_id, employee_id) do
    with :ok <- authorize(scope, "admin.employee.delete"),
         {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)),
         %Schema{} = employee <- employee_schema(company_id, employee_id) do
      if platform_orchestrator_record?(employee) do
        {:error, :invariant_violation}
      else
        Repo.transaction(fn ->
          lock_company_or_rollback(scope, employee.company_id)
          :ok = Person.lock_legacy_employee(scope, employee.id)
          owner = EmploymentOwner.registered()
          mapping = owner && legacy_mapping(scope, employee.id)

          case Repo.delete(employee) do
            {:ok, _} ->
              :ok = Person.end_legacy_employee_affiliation(scope, employee.id)
              notify_owner_or_rollback(owner, scope, employee.id, mapping)

            {:error, _} ->
              Repo.rollback(:invariant_violation)
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end
    else
      {:error, :forbidden} = error -> error
      {:error, reason} = error when reason in [:company_not_found, :company_archived] -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @spec ensure_system_types(Ecto.Repo.t()) :: :ok | {:error, :invariant_violation}
  def ensure_system_types(repo \\ Repo) do
    with :ok <- assert_system_type_bootstrap_safe(repo) do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      rows =
        Enum.map(@system_types, fn type ->
          Map.merge(type, %{
            is_system: true,
            company_id: nil,
            created_at: now,
            updated_at: now
          })
        end)

      # The system employee types are fixture data reconciled under the
      # production seeds, not an actor's decision. The upsert's conflict
      # target is an index predicate, which capture cannot read to tell an
      # insert from a replacement, so saying so here is also what keeps it
      # from reporting an unclassifiable upsert on every seed run.
      WriteCapture.without_capture(fn ->
        repo.insert_all(EmployeeType, rows,
          conflict_target:
            {:unsafe_fragment, "(code) WHERE company_id IS NULL AND is_system = true"},
          on_conflict: {:replace, [:label, :is_system, :company_id, :updated_at]}
        )
      end)

      :ok
    end
  end

  @doc "Resolves Bilimbi's platform orchestrator without assigning meaning to a numeric ID."
  @spec platform_orchestrator() :: {:ok, Summary.t()} | {:error, lookup_error()}
  def platform_orchestrator do
    with {:ok, company} <- Company.platform_operator_company(),
         {:ok, employee} <- resolve_platform_orchestrator(company.id) do
      {:ok, Summary.from_schema(employee)}
    end
  end

  @doc "Idempotently provisions the platform orchestrator in the platform-operator company."
  @spec ensure_platform_orchestrator() ::
          {:ok, Summary.t(), provision_status()} | {:error, lookup_error() | Changeset.t()}
  def ensure_platform_orchestrator do
    with {:ok, company} <- Company.platform_operator_company(),
         :ok <- ensure_system_types() do
      case resolve_platform_orchestrator(company.id) do
        {:ok, employee} ->
          {:ok, Summary.from_schema(employee), :existing}

        {:error, :not_provisioned} ->
          insert_platform_orchestrator(company)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec list_employee_types(Scope.t(), pos_integer()) ::
          {:ok, [TypeSummary.t()]} | {:error, :company_not_found}
  def list_employee_types(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)) do
      types =
        from(type in EmployeeType,
          where:
            (type.is_system == true and is_nil(type.company_id)) or
              type.company_id == ^company_id,
          order_by: [desc: type.is_system, asc: type.label, asc: type.code]
        )
        |> Repo.all()
        |> Enum.map(&TypeSummary.from_schema/1)

      {:ok, types}
    end
  end

  @doc """
  Returns one bounded, deterministic employee types administration page for a live company.

  Options are a plain keyword list. Supported values are `:page`, `:page_size`,
  `:search`, `:sort_by` (`:code`, `:label`, `:is_system`, or `:employees_count`),
  and `:sort_dir` (`:asc` or `:desc`).
  """
  @spec list_type_administration_page(Scope.t(), pos_integer(), keyword()) ::
          {:ok, TypeAdministrationPage.t()} | {:error, :company_not_found | :invalid_options}
  def list_type_administration_page(scope, company_id, options \\ [])

  def list_type_administration_page(%Scope{} = scope, company_id, options)
      when is_integer(company_id) and company_id > 0 do
    with {:ok, normalized_options} <- TypeAdministrationIndex.normalize_options(options),
         {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)) do
      {:ok, TypeAdministrationIndex.page(company_id, normalized_options)}
    end
  end

  def list_type_administration_page(%Scope{}, _company_id, _options),
    do: {:error, :company_not_found}

  @doc "Resolves one employee type visible to the company."
  @spec get_employee_type(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, TypeSummary.t()} | {:error, :company_not_found | :type_not_found}
  def get_employee_type(%Scope{} = scope, company_id, type_id)
      when is_integer(company_id) and is_integer(type_id) do
    with {:ok, _company} <- normalize_company(Company.require_live_company(scope, company_id)) do
      case Repo.get(EmployeeType, type_id) do
        nil ->
          {:error, :type_not_found}

        %EmployeeType{is_system: true, company_id: nil} = type ->
          {:ok, TypeSummary.from_schema(type)}

        %EmployeeType{company_id: ^company_id} = type ->
          {:ok, TypeSummary.from_schema(type)}

        %EmployeeType{} ->
          {:error, :type_not_found}
      end
    end
  end

  @spec create_employee_type(Scope.t(), pos_integer(), map()) ::
          {:ok, TypeSummary.t()}
          | {:error, :company_not_found | :company_archived | Changeset.t()}
  def create_employee_type(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)),
         {:ok, type} <-
           company_id
           |> EmployeeType.custom_changeset(attributes)
           |> reject_reserved_system_type_code()
           |> Repo.insert() do
      {:ok, TypeSummary.from_schema(type)}
    end
  end

  @spec update_employee_type(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, TypeSummary.t()}
          | {:error,
             :company_not_found | :company_archived | :type_not_found | :is_system | Changeset.t()}
  def update_employee_type(%Scope{} = scope, company_id, type_id, attributes)
      when is_integer(company_id) and is_integer(type_id) and is_map(attributes) do
    with {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)),
         {:ok, type} <- fetch_company_employee_type(company_id, type_id) do
      type
      |> EmployeeType.update_changeset(attributes)
      |> Repo.update()
      |> case do
        {:ok, updated_type} -> {:ok, TypeSummary.from_schema(updated_type)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @spec delete_employee_type(Scope.t(), pos_integer(), pos_integer()) ::
          :ok
          | {:error,
             :company_not_found
             | :company_archived
             | :type_not_found
             | :is_system
             | :in_use
             | :forbidden}
  def delete_employee_type(%Scope{} = scope, company_id, type_id)
      when is_integer(company_id) and is_integer(type_id) do
    with :ok <- authorize(scope, "admin.employee-type.delete"),
         {:ok, _company} <- normalize_company(Company.require_writable_company(scope, company_id)) do
      Repo.transaction(fn ->
        case Repo.one(
               from(type in EmployeeType,
                 where: type.id == ^type_id,
                 lock: "FOR UPDATE"
               )
             ) do
          nil ->
            Repo.rollback(:type_not_found)

          %EmployeeType{is_system: true} ->
            Repo.rollback(:is_system)

          %EmployeeType{company_id: owner_id} when owner_id != company_id ->
            Repo.rollback(:type_not_found)

          %EmployeeType{company_id: ^company_id, code: code} = type ->
            in_use? =
              Repo.exists?(
                from(employee in Schema,
                  where: employee.company_id == ^company_id and employee.employee_type == ^code
                )
              )

            if in_use? do
              Repo.rollback(:in_use)
            else
              case Repo.delete(type) do
                {:ok, _} -> :ok
                {:error, reason} -> Repo.rollback(reason)
              end
            end
        end
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :forbidden} = error -> error
      {:error, reason} = error when reason in [:company_not_found, :company_archived] -> error
    end
  end

  defp list_company_summaries(company_id) do
    Schema
    |> EmployeeType.with_resolved_type()
    |> where([employee], employee.company_id == ^company_id)
    |> order_by([employee], asc: employee.id)
    |> select(
      [employee, company_type, global_type],
      {employee, coalesce(company_type.label, global_type.label)}
    )
    |> Repo.all()
    |> Enum.map(&Summary.from_query_result/1)
  end

  # The delete screens already ask for these capabilities. Seeds, mix tasks,
  # and `Tenancy.scope/1` pass the anonymous system actor, which holds no
  # grants; a person and a named system principal are decided by Authz.
  defp authorize(%Scope{} = scope, capability) do
    actor = Scope.actor(scope)

    if TenancyActor.system?(actor) and is_nil(TenancyActor.system_principal(actor)) do
      :ok
    else
      case Authz.can(scope, capability) do
        %{allowed: true} -> :ok
        %{allowed: false} -> {:error, :forbidden}
      end
    end
  end

  defp fetch_company_employee_type(company_id, type_id) do
    case Repo.get(EmployeeType, type_id) do
      nil ->
        {:error, :type_not_found}

      %EmployeeType{is_system: true} ->
        {:error, :is_system}

      %EmployeeType{company_id: owner_id} when owner_id != company_id ->
        {:error, :type_not_found}

      %EmployeeType{company_id: ^company_id} = type ->
        {:ok, type}
    end
  end

  @spec addressable_identity() :: String.t()
  def addressable_identity, do: "App\\Core\\Employee\\Models\\Employee"

  defp validate_references(changeset, scope, company_id, employee_id) do
    changeset
    |> validate_department(scope, company_id)
    |> validate_supervisor(company_id, employee_id)
    |> validate_employee_type(company_id)
  end

  defp validate_department(changeset, scope, company_id) do
    case Changeset.get_field(changeset, :department_id) do
      nil ->
        changeset

      department_id ->
        if Company.department_belongs_to_company?(scope, company_id, department_id) do
          changeset
        else
          Changeset.add_error(changeset, :department_id, "does not belong to the company")
        end
    end
  end

  defp validate_supervisor(changeset, company_id, employee_id) do
    case Changeset.get_field(changeset, :supervisor_id) do
      nil ->
        changeset

      ^employee_id when not is_nil(employee_id) ->
        Changeset.add_error(changeset, :supervisor_id, "cannot reference the employee itself")

      supervisor_id ->
        if Repo.exists?(
             from(employee in Schema,
               where: employee.id == ^supervisor_id and employee.company_id == ^company_id
             )
           ) do
          changeset
        else
          Changeset.add_error(changeset, :supervisor_id, "does not belong to the company")
        end
    end
  end

  defp validate_employee_type(changeset, company_id) do
    case Changeset.get_field(changeset, :employee_type) do
      nil ->
        changeset

      code ->
        if Repo.exists?(
             from(type in EmployeeType,
               where:
                 type.code == ^code and
                   ((type.is_system == true and is_nil(type.company_id)) or
                      type.company_id == ^company_id)
             )
           ) do
          changeset
        else
          Changeset.add_error(changeset, :employee_type, "is not available to the company")
        end
    end
  end

  defp reject_reserved_orchestrator_number(changeset, existing \\ nil)

  defp reject_reserved_orchestrator_number(changeset, nil) do
    case Changeset.get_field(changeset, :employee_number) do
      @platform_orchestrator_number ->
        Changeset.add_error(
          changeset,
          :employee_number,
          "is reserved for the platform orchestrator"
        )

      _ ->
        changeset
    end
  end

  defp reject_reserved_orchestrator_number(changeset, %Schema{} = existing) do
    if platform_orchestrator_record?(existing) do
      changeset
    else
      reject_reserved_orchestrator_number(changeset, nil)
    end
  end

  defp protect_platform_orchestrator_identity(changeset, employee) do
    if platform_orchestrator_record?(employee) do
      Enum.reduce(@protected_orchestrator_fields, changeset, fn field, result ->
        case Changeset.fetch_change(result, field) do
          :error ->
            result

          {:ok, value} ->
            if value == Map.fetch!(employee, field) do
              result
            else
              Changeset.add_error(
                result,
                field,
                "cannot change the platform orchestrator identity"
              )
            end
        end
      end)
    else
      changeset
    end
  end

  defp reject_reserved_system_type_code(%Changeset{valid?: false} = changeset), do: changeset

  defp reject_reserved_system_type_code(changeset) do
    case Changeset.get_field(changeset, :code) do
      code when code in @system_type_codes ->
        Changeset.add_error(changeset, :code, "is reserved for a system employee type")

      _ ->
        changeset
    end
  end

  defp assert_system_type_bootstrap_safe(repo) do
    conflicts =
      from(type in EmployeeType,
        where:
          type.code in ^@system_type_codes and
            (type.is_system != true or not is_nil(type.company_id)),
        select: type.code
      )
      |> repo.all()

    if conflicts == [] do
      :ok
    else
      {:error, :invariant_violation}
    end
  end

  defp resolve_platform_orchestrator(operator_company_id) do
    case Repo.all(
           from(employee in Schema,
             where: employee.employee_number == ^@platform_orchestrator_number,
             order_by: employee.id
           )
         ) do
      [] ->
        {:error, :not_provisioned}

      employees ->
        case Enum.split_with(employees, &platform_orchestrator_record?/1) do
          {[], _} ->
            {:error, :invariant_violation}

          {[orchestrator], []} ->
            if orchestrator.company_id == operator_company_id do
              {:ok, orchestrator}
            else
              # Primary-company transfer left the durable SYS-001 agent on the
              # previous company. Fail closed rather than minting a second one.
              {:error, :invariant_violation}
            end

          _ ->
            {:error, :invariant_violation}
        end
    end
  end

  defp employee_schema(company_id, employee_id) do
    Repo.get_by(Schema, id: employee_id, company_id: company_id)
  end

  defp insert_platform_orchestrator(company) do
    attributes =
      Map.put(@platform_orchestrator_attributes, :employment_start, Date.utc_today())

    changeset = Schema.creation_changeset(company.id, attributes)

    case insert_orchestrator(company, changeset) do
      {:ok, employee} ->
        {:ok, Summary.from_schema(employee), :created}

      {:error, changeset} ->
        case resolve_platform_orchestrator(company.id) do
          {:ok, employee} -> {:ok, Summary.from_schema(employee), :existing}
          {:error, :not_provisioned} -> {:error, changeset}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp insert_orchestrator(company, changeset) do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(company.tenant_id)

    Repo.transaction(fn ->
      owner = EmploymentOwner.registered()
      if owner, do: lock_company_or_rollback(scope, company.id)

      case Repo.insert(changeset) do
        {:ok, employee} ->
          :ok = sync_person(scope, employee, person_facts(employee))
          notify_owner_or_rollback(owner, scope, employee.id)
          employee

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp platform_orchestrator_record?(%Schema{
         employee_number: @platform_orchestrator_number,
         employee_type: @platform_orchestrator_type
       }),
       do: true

  defp platform_orchestrator_record?(%Schema{}), do: false

  defp persist_insert(%Changeset{valid?: false} = changeset, _scope), do: {:error, changeset}

  defp persist_insert(changeset, scope) do
    Repo.transaction(fn ->
      owner = EmploymentOwner.registered()
      if owner, do: lock_company_or_rollback(scope, Changeset.get_field(changeset, :company_id))

      case Repo.insert(changeset) do
        {:ok, employee} ->
          case sync_person(scope, employee, person_facts(employee)) do
            :ok ->
              notify_owner_or_rollback(owner, scope, employee.id)
              Summary.from_schema(employee)

            {:error, person_cs} ->
              Repo.rollback(reject_person_sync(changeset, person_cs, :insert))
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp persist_update(%Changeset{valid?: false} = changeset, _scope), do: {:error, changeset}

  defp persist_update(changeset, scope) do
    facts = person_facts(changeset.changes)

    Repo.transaction(fn ->
      lock_company_or_rollback(scope, changeset.data.company_id)
      :ok = Person.lock_legacy_employee(scope, changeset.data.id)
      owner = EmploymentOwner.registered()

      case Repo.update(changeset) do
        {:ok, employee} ->
          case sync_person(scope, employee, facts, person_facts(employee)) do
            :ok ->
              notify_owner_or_rollback(owner, scope, employee.id)
              Summary.from_schema(employee)

            {:error, person_cs} ->
              Repo.rollback(reject_person_sync(changeset, person_cs, :update))
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # The owner is read inside the transaction, after Core's locks (a company
  # lock first, for an insert, only when an owner is registered), so one write
  # either calls it or does not. It runs after Core's own write.
  defp notify_owner_or_rollback(nil, _scope, _employee_id), do: :ok

  defp notify_owner_or_rollback(owner, scope, employee_id),
    do: notify_owner_or_rollback(owner, scope, employee_id, legacy_mapping(scope, employee_id))

  defp notify_owner_or_rollback(nil, _scope, _employee_id, _mapping), do: :ok

  defp notify_owner_or_rollback(owner, scope, employee_id, mapping) do
    case owner.legacy_employee_written(scope, %{
           employee_id: employee_id,
           person_id: mapping[:person_id],
           affiliation_id: mapping[:affiliation_id]
         }) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp legacy_mapping(scope, employee_id),
    do: scope |> Person.legacy_mappings([employee_id]) |> Map.get(employee_id)

  defp identity_batch(employee_ids) when is_list(employee_ids) do
    employee_ids = Enum.uniq(employee_ids)

    if length(employee_ids) <= @identity_batch_limit and
         Enum.all?(employee_ids, &(is_integer(&1) and &1 > 0)),
       do: {:ok, employee_ids},
       else: {:error, :invalid_options}
  end

  defp identity_batch(_employee_ids), do: {:error, :invalid_options}

  defp tenant_employee_ids(_scope, []), do: []

  defp tenant_employee_ids(scope, employee_ids) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    from(employee in Schema,
      where: employee.id in ^employee_ids and employee.company_id in ^company_ids,
      select: employee.id
    )
    |> Repo.all()
  end

  defp handoff_cursor(nil), do: {:ok, 0}
  defp handoff_cursor(cursor) when is_integer(cursor) and cursor > 0, do: {:ok, cursor}
  defp handoff_cursor(_cursor), do: {:error, :invalid_options}

  defp handoff_limit(options) when is_list(options) do
    case Keyword.get(options, :limit, @handoff_page_size) do
      limit when is_integer(limit) and limit > 0 and limit <= @identity_batch_limit ->
        {:ok, limit}

      _ ->
        {:error, :invalid_options}
    end
  end

  defp handoff_limit(_options), do: {:error, :invalid_options}

  defp sync_person(scope, %Schema{} = employee, facts, initial_facts \\ nil),
    do:
      Person.sync_legacy_employee(
        scope,
        employee.id,
        employee.company_id,
        facts,
        initial_facts
      )

  # Re-prove writability inside the transaction, before Person/affiliation and Employee locks.
  defp lock_company_or_rollback(scope, company_id) do
    case normalize_company(Company.lock_writable_company(scope, company_id)) do
      {:ok, _proof} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reject_person_sync(%Changeset{} = changeset, %Changeset{errors: errors}, action) do
    Enum.reduce(errors, %{changeset | action: action}, fn {fact, {message, _}}, acc ->
      case Enum.find(@person_fact_fields, fn {_field, mapped} -> mapped == fact end) do
        {field, _fact} ->
          Changeset.add_error(acc, field, "conflicts with the Contacts affiliation: #{message}")

        nil ->
          acc
      end
    end)
  end

  defp person_facts(%Schema{} = employee), do: employee |> Map.from_struct() |> person_facts()

  defp person_facts(fields) when is_map(fields) do
    for {field, fact} <- @person_fact_fields, Map.has_key?(fields, field), into: %{} do
      {fact, Map.fetch!(fields, field)}
    end
  end

  defp normalize_company({:ok, company}), do: {:ok, company}
  defp normalize_company({:error, :not_found}), do: {:error, :company_not_found}
  defp normalize_company({:error, :company_archived}), do: {:error, :company_archived}
end
