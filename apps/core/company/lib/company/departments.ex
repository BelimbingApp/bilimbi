defmodule Bilimbi.Core.Company.Departments do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.WritableCompany

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

  # A write on a department begins with `WritableCompany.fetch_parent/2`:
  # an archived company's departments are read-only (`:company_archived`).
  @spec create_department(Scope.t(), pos_integer(), map()) ::
          {:ok, Department.t()}
          | {:error, :company_not_found | :company_archived | Ecto.Changeset.t()}
  def create_department(%Scope{} = scope, company_id, attrs) do
    case WritableCompany.fetch_parent(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

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
          {:ok, Department.t()}
          | {:error, :company_not_found | :company_archived | :not_found | Ecto.Changeset.t()}
  def update_department_status(%Scope{} = scope, company_id, department_id, status) do
    case WritableCompany.fetch_parent(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

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

  @spec update_department_head(Scope.t(), pos_integer(), pos_integer(), pos_integer() | nil) ::
          {:ok, Department.t()}
          | {:error, :company_not_found | :company_archived | :not_found | Ecto.Changeset.t()}
  def update_department_head(%Scope{} = scope, company_id, department_id, head_id) do
    case WritableCompany.fetch_parent(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

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
            |> Department.head_changeset(head_id)
            |> Repo.update()
        end
    end
  end

  @spec delete_department(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :company_not_found | :company_archived | :not_found}
  def delete_department(%Scope{} = scope, company_id, department_id) do
    case WritableCompany.fetch_parent(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

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

  # Same live row as get_company/2. These aggregates treat a miss as the parent
  # company being gone, so :not_found becomes :company_not_found.
  defp live_company(%Scope{} = scope, company_id)
       when is_integer(company_id) and company_id > 0 do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)
      )

    case Repo.one(query) do
      nil -> {:error, :company_not_found}
      company -> {:ok, company}
    end
  end

  defp live_company(%Scope{}, _company_id), do: {:error, :company_not_found}
end
