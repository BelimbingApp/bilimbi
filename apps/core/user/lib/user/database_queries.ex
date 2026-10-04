defmodule Bilimbi.Core.User.DatabaseQueries do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.DatabaseQuery

  @doc """
  Lists saved database queries owned by the given user ID within the tenant scope.
  """
  @spec list_database_queries(Scope.t(), keyword()) ::
          {:ok, [DatabaseQuery.t()]} | {:error, :user_not_found | :unauthorized}
  def list_database_queries(%Scope{} = scope, opts \\ []) when is_list(opts) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      search = Keyword.get(opts, :search)
      sort_by = Keyword.get(opts, :sort_by, :name)
      sort_dir = Keyword.get(opts, :sort_dir, :asc)

      base_query = from(q in DatabaseQuery, where: q.user_id == ^user_id)

      query =
        if is_binary(search) and String.trim(search) != "" do
          pattern = "%#{String.trim(search)}%"
          from(q in base_query, where: ilike(q.name, ^pattern) or ilike(q.description, ^pattern))
        else
          base_query
        end

      order_field =
        case sort_by do
          :name -> :name
          :description -> :description
          :created_at -> :created_at
          :updated_at -> :updated_at
          "name" -> :name
          "description" -> :description
          "created_at" -> :created_at
          "updated_at" -> :updated_at
          _ -> :name
        end

      order_expr =
        if sort_dir in [:desc, "desc", "DESC"] do
          [desc: order_field, desc: :id]
        else
          [asc: order_field, asc: :id]
        end

      queries =
        from(q in query, order_by: ^order_expr)
        |> Repo.all()

      {:ok, queries}
    end
  end

  @doc """
  Fetches a database query owned by the user by integer ID or binary slug within the tenant scope.
  """
  @spec get_database_query(Scope.t(), pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :not_found | :unauthorized}
  def get_database_query(%Scope{} = scope, id) when is_integer(id) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      case Repo.get_by(DatabaseQuery, id: id, user_id: user_id) do
        nil -> {:error, :not_found}
        %DatabaseQuery{} = query -> {:ok, query}
      end
    end
  end

  def get_database_query(%Scope{} = scope, slug) when is_binary(slug) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      case Repo.get_by(DatabaseQuery, slug: slug, user_id: user_id) do
        nil -> {:error, :not_found}
        %DatabaseQuery{} = query -> {:ok, query}
      end
    end
  end

  def get_database_query(%Scope{} = scope, _invalid) do
    case subject(scope) do
      {:ok, _} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a new saved database query for the given user ID within the tenant scope.
  """
  @spec create_database_query(Scope.t(), map()) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :unauthorized | Changeset.t()}
  def create_database_query(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      user_id
      |> DatabaseQuery.creation_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates an existing database query owned by the user within the tenant scope.
  """
  @spec update_database_query(Scope.t(), DatabaseQuery.t() | pos_integer() | String.t(), map()) ::
          {:ok, DatabaseQuery.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  def update_database_query(%Scope{} = scope, %DatabaseQuery{} = query, attrs)
      when is_map(attrs) do
    with {:ok, user_id} <- subject(scope),
         :ok <- owned_by(query, user_id),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      query
      |> DatabaseQuery.changeset(attrs)
      |> Repo.update()
    end
  end

  def update_database_query(%Scope{} = scope, id_or_slug, attrs) when is_map(attrs) do
    with {:ok, query} <- get_database_query(scope, id_or_slug) do
      update_database_query(scope, query, attrs)
    end
  end

  @doc """
  Deletes a saved database query owned by the user within the tenant scope.
  """
  @spec delete_database_query(Scope.t(), DatabaseQuery.t() | pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  def delete_database_query(%Scope{} = scope, %DatabaseQuery{} = query) do
    with {:ok, user_id} <- subject(scope),
         :ok <- owned_by(query, user_id),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      Repo.delete(query)
    end
  end

  def delete_database_query(%Scope{} = scope, id_or_slug) do
    with {:ok, query} <- get_database_query(scope, id_or_slug) do
      delete_database_query(scope, query)
    end
  end

  @doc """
  Duplicates an existing database query for the user, assigning a new unique slug.
  """
  @spec duplicate_database_query(Scope.t(), DatabaseQuery.t() | pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  def duplicate_database_query(%Scope{} = scope, id_or_slug) do
    with {:ok, original} <- get_database_query(scope, id_or_slug) do
      attrs = %{
        name: "#{original.name} (Copy)",
        prompt: original.prompt,
        sql_query: original.sql_query,
        description: original.description,
        icon: original.icon
      }

      create_database_query(scope, attrs)
    end
  end

  @doc """
  Generates a unique slug for a query name scoped to the signed-in user.
  """
  @spec generate_query_slug(Scope.t(), String.t()) ::
          {:ok, String.t()} | {:error, :unauthorized}
  def generate_query_slug(%Scope{} = scope, name) when is_binary(name) do
    with {:ok, user_id} <- subject(scope) do
      {:ok, DatabaseQuery.generate_slug(user_id, name)}
    end
  end

  defp owned_by(%DatabaseQuery{user_id: user_id}, user_id), do: :ok
  defp owned_by(%DatabaseQuery{}, _user_id), do: {:error, :not_found}

  defp subject(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id} when is_integer(user_id) and user_id > 0 ->
        {:ok, user_id}

      %TenancyActor{} ->
        {:error, :unauthorized}
    end
  end
end
