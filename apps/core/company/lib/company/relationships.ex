defmodule Bilimbi.Core.Company.Relationships do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Relationship
  alias Bilimbi.Core.Company.RelationshipType
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary

  @update_capability "admin.company.update"

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
            preload: [type: t],
            select: {r, rc}
          )
          |> Repo.all()

        incoming =
          from(r in Relationship,
            join: c in assoc(r, :company),
            join: t in assoc(r, :type),
            where:
              r.related_company_id == ^company_id and is_nil(r.deleted_at) and
                is_nil(c.deleted_at),
            preload: [type: t],
            select: {r, c}
          )
          |> Repo.all()

        summaries =
          (outgoing ++ incoming)
          |> Enum.map(&elem(&1, 1))
          |> Summary.for_scope(scope)
          |> Map.new(&{&1.id, &1})

        all_rels =
          (Enum.map(outgoing, &item(&1, :outgoing, summaries)) ++
             Enum.map(incoming, &item(&1, :incoming, summaries)))
          |> Enum.sort_by(fn item -> {item.other_company.name, item.type.name} end)

        {:ok, all_rels}
    end
  end

  defp item({r, other}, direction, summaries) do
    %{
      id: r.id,
      direction: direction,
      relationship: r,
      type: r.type,
      other_company: Map.fetch!(summaries, other.id),
      effective_from: r.effective_from,
      effective_to: r.effective_to,
      is_active: Relationship.active?(r)
    }
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
          |> Summary.for_scope(scope)

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
          | {:error,
             :forbidden | :company_not_found | :related_company_not_found | Ecto.Changeset.t()}
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

    with :ok <- authorize(scope, @update_capability),
         {:ok, _company} <- live_company(scope, company_id) do
      if related_id != nil do
        case live_company(scope, related_id) do
          {:ok, _related} ->
            %Relationship{company_id: company_id}
            |> Relationship.changeset(attrs)
            |> Repo.insert()
            |> case do
              {:ok, rel} -> {:ok, Repo.preload(rel, [:type])}
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
          | {:error, :forbidden | :company_not_found | :not_found | Ecto.Changeset.t()}
  def update_relationship(%Scope{} = scope, company_id, relationship_id, attrs) do
    with :ok <- authorize(scope, @update_capability) do
      update_relationship_record(scope, company_id, relationship_id, attrs)
    end
  end

  defp update_relationship_record(%Scope{} = scope, company_id, relationship_id, attrs) do
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
            preload: [:type]
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
          :ok | {:error, :forbidden | :company_not_found | :not_found}
  def delete_relationship(%Scope{} = scope, company_id, relationship_id) do
    with :ok <- authorize(scope, @update_capability) do
      delete_relationship_record(scope, company_id, relationship_id)
    end
  end

  defp delete_relationship_record(%Scope{} = scope, company_id, relationship_id) do
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

  defp now do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
