defmodule Bilimbi.Core.Company.ReferenceTypes do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.LegalEntityType
  alias Bilimbi.Core.Company.Schema

  @create_capability "admin.company.create"
  @update_capability "admin.company.update"
  @delete_capability "admin.company.delete"

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

  @spec create_legal_entity_type(Scope.t(), map()) ::
          {:ok, LegalEntityType.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def create_legal_entity_type(%Scope{} = scope, attrs) when is_map(attrs) do
    with :ok <- authorize(scope, @create_capability) do
      %LegalEntityType{}
      |> LegalEntityType.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec update_legal_entity_type(Scope.t(), pos_integer() | LegalEntityType.t(), map()) ::
          {:ok, LegalEntityType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  def update_legal_entity_type(%Scope{} = scope, %LegalEntityType{} = type, attrs) do
    with :ok <- authorize(scope, @update_capability) do
      type
      |> LegalEntityType.update_changeset(attrs)
      |> Repo.update()
    end
  end

  def update_legal_entity_type(%Scope{} = scope, id, attrs) when is_integer(id) and id > 0 do
    with :ok <- authorize(scope, @update_capability) do
      case Repo.get(LegalEntityType, id) do
        nil ->
          {:error, :not_found}

        type ->
          type
          |> LegalEntityType.update_changeset(attrs)
          |> Repo.update()
      end
    end
  end

  def update_legal_entity_type(%Scope{} = scope, _id, _attrs) do
    with :ok <- authorize(scope, @update_capability), do: {:error, :not_found}
  end

  @spec toggle_legal_entity_type_active(Scope.t(), pos_integer()) ::
          {:ok, LegalEntityType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  def toggle_legal_entity_type_active(%Scope{} = scope, id) when is_integer(id) and id > 0 do
    with :ok <- authorize(scope, @update_capability) do
      case Repo.get(LegalEntityType, id) do
        nil ->
          {:error, :not_found}

        type ->
          type
          |> Ecto.Changeset.change(is_active: not type.is_active)
          |> Repo.update()
      end
    end
  end

  def toggle_legal_entity_type_active(%Scope{} = scope, _id) do
    with :ok <- authorize(scope, @update_capability), do: {:error, :not_found}
  end

  @spec delete_legal_entity_type(Scope.t(), pos_integer()) ::
          :ok | {:error, :forbidden | :not_found | :in_use}
  def delete_legal_entity_type(%Scope{} = scope, id) when is_integer(id) and id > 0 do
    with :ok <- authorize(scope, @delete_capability) do
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
  end

  def delete_legal_entity_type(%Scope{} = scope, _id) do
    with :ok <- authorize(scope, @delete_capability), do: {:error, :not_found}
  end

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

  @spec create_department_type(Scope.t(), map()) ::
          {:ok, DepartmentType.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def create_department_type(%Scope{} = scope, attrs) when is_map(attrs) do
    with :ok <- authorize(scope, @create_capability) do
      %DepartmentType{}
      |> DepartmentType.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec update_department_type(Scope.t(), pos_integer() | DepartmentType.t(), map()) ::
          {:ok, DepartmentType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  def update_department_type(%Scope{} = scope, %DepartmentType{} = type, attrs) do
    with :ok <- authorize(scope, @update_capability) do
      type
      |> DepartmentType.update_changeset(attrs)
      |> Repo.update()
    end
  end

  def update_department_type(%Scope{} = scope, id, attrs) when is_integer(id) and id > 0 do
    with :ok <- authorize(scope, @update_capability) do
      case Repo.get(DepartmentType, id) do
        nil ->
          {:error, :not_found}

        type ->
          type
          |> DepartmentType.update_changeset(attrs)
          |> Repo.update()
      end
    end
  end

  def update_department_type(%Scope{} = scope, _id, _attrs) do
    with :ok <- authorize(scope, @update_capability), do: {:error, :not_found}
  end

  @spec toggle_department_type_active(Scope.t(), pos_integer()) ::
          {:ok, DepartmentType.t()} | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
  def toggle_department_type_active(%Scope{} = scope, id) when is_integer(id) and id > 0 do
    with :ok <- authorize(scope, @update_capability) do
      case Repo.get(DepartmentType, id) do
        nil ->
          {:error, :not_found}

        type ->
          type
          |> Ecto.Changeset.change(is_active: not type.is_active)
          |> Repo.update()
      end
    end
  end

  def toggle_department_type_active(%Scope{} = scope, _id) do
    with :ok <- authorize(scope, @update_capability), do: {:error, :not_found}
  end

  @spec delete_department_type(Scope.t(), pos_integer()) ::
          :ok | {:error, :forbidden | :not_found | :in_use}
  def delete_department_type(%Scope{} = scope, id) when is_integer(id) and id > 0 do
    with :ok <- authorize(scope, @delete_capability) do
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
  end

  def delete_department_type(%Scope{} = scope, _id) do
    with :ok <- authorize(scope, @delete_capability), do: {:error, :not_found}
  end

  # Type and relationship screens already ask for these capabilities. Seeds,
  # mix tasks, and `Tenancy.scope/1` pass the anonymous system actor, which
  # holds no grants; a person and a named system principal are decided by Authz.
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
end
