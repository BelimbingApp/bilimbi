defmodule Bilimbi.Core.Employee do
  @moduledoc """
  Public API for tenant-scoped employment relationships.

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

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.Schema
  alias Bilimbi.Core.Employee.Summary
  alias Bilimbi.Core.Employee.TypeSummary
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

  @type lookup_error ::
          :company_not_found
          | :employee_not_found
          | :not_provisioned
          | :invariant_violation
          | :database_unavailable

  @type provision_status :: :created | :existing

  @spec list_employees(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_employees(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
      employees =
        from(employee in Schema,
          where: employee.company_id == ^company_id,
          order_by: employee.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, employees}
    end
  end

  @spec get_employee(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, lookup_error()}
  def get_employee(%Scope{} = scope, company_id, employee_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = employee <- employee_schema(company_id, employee_id) do
      {:ok, Summary.from_schema(employee)}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @doc "Resolves an employee through any live company visible to the tenant scope."
  @spec get_employee(Scope.t(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :employee_not_found}
  def get_employee(%Scope{} = scope, employee_id) do
    {:ok, companies} = Company.list_companies(scope)
    company_ids = Enum.map(companies, & &1.id)

    case Repo.one(
           from(employee in Schema,
             where: employee.id == ^employee_id and employee.company_id in ^company_ids
           )
         ) do
      nil -> {:error, :employee_not_found}
      employee -> {:ok, Summary.from_schema(employee)}
    end
  end

  @spec create_employee(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :company_not_found | Changeset.t()}
  def create_employee(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
      company_id
      |> Schema.creation_changeset(attributes)
      |> reject_reserved_orchestrator_number()
      |> validate_references(scope, company_id, nil)
      |> persist_insert()
    end
  end

  @spec update_employee(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | Changeset.t()}
  def update_employee(%Scope{} = scope, company_id, employee_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = employee <- employee_schema(company_id, employee_id) do
      employee
      |> Schema.update_changeset(attributes)
      |> protect_platform_orchestrator_identity(employee)
      |> reject_reserved_orchestrator_number(employee)
      |> validate_references(scope, company_id, employee_id)
      |> persist_update()
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :employee_not_found}
    end
  end

  @spec delete_employee(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, lookup_error()}
  def delete_employee(%Scope{} = scope, company_id, employee_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = employee <- employee_schema(company_id, employee_id) do
      if platform_orchestrator_record?(employee) do
        {:error, :invariant_violation}
      else
        case Repo.delete(employee) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :invariant_violation}
        end
      end
    else
      {:error, :company_not_found} = error -> error
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

      repo.insert_all(EmployeeType, rows,
        conflict_target: [:code],
        on_conflict: {:replace, [:label, :is_system, :company_id, :updated_at]}
      )

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
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
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

  @spec create_employee_type(Scope.t(), pos_integer(), map()) ::
          {:ok, TypeSummary.t()} | {:error, :company_not_found | Changeset.t()}
  def create_employee_type(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         {:ok, type} <-
           company_id
           |> EmployeeType.custom_changeset(attributes)
           |> reject_reserved_system_type_code()
           |> Repo.insert() do
      {:ok, TypeSummary.from_schema(type)}
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

    case Repo.insert(changeset) do
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

  defp platform_orchestrator_record?(%Schema{
         employee_number: @platform_orchestrator_number,
         employee_type: @platform_orchestrator_type
       }),
       do: true

  defp platform_orchestrator_record?(%Schema{}), do: false

  defp persist_insert(%Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_insert(changeset) do
    case Repo.insert(changeset) do
      {:ok, employee} -> {:ok, Summary.from_schema(employee)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp persist_update(%Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_update(changeset) do
    case Repo.update(changeset) do
      {:ok, employee} -> {:ok, Summary.from_schema(employee)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp normalize_company({:ok, company}), do: {:ok, company}
  defp normalize_company({:error, :not_found}), do: {:error, :company_not_found}
end
