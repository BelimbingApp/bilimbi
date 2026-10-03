defmodule Bilimbi.Core.Company.ExternalAccesses do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.ExternalAccess
  alias Bilimbi.Core.Company.ExternalAccessSummary
  alias Bilimbi.Core.Company.Relationship
  alias Bilimbi.Core.Company.Schema

  @list_limit 200

  @type access_lookup_error :: :not_found | :company_not_found | :relationship_not_found

  @spec list_external_accesses(Scope.t(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_external_accesses(%Scope{} = scope, company_id) do
    list_accesses(scope, company_id, :all)
  end

  @spec list_external_accesses(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, [ExternalAccessSummary.t()]} | {:error, :company_not_found}
  def list_external_accesses(%Scope{} = scope, company_id, user_id)
      when is_integer(user_id) and user_id > 0 do
    list_accesses(scope, company_id, user_id)
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

  defp list_accesses(scope, company_id, user_filter) do
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

  defp now do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
