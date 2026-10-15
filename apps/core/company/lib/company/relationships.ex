defmodule Bilimbi.Core.Company.Relationships do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Relationship
  alias Bilimbi.Core.Company.RelationshipType
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary
  alias Bilimbi.Core.Company.WritableCompany

  @update_capability "admin.company.update"

  @spec list_relationships(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, :company_not_found}
  def list_relationships(%Scope{} = scope, company_id, opts \\ []) do
    case live_company(scope, company_id) do
      {:error, :company_not_found} ->
        {:error, :company_not_found}

      {:ok, _company} ->
        include_unlinked? = Keyword.get(opts, :include_unlinked, false) == true
        scoped_companies = Tenancy.scope_query(Schema, scope)

        outgoing =
          from(r in Relationship,
            join: rc in ^scoped_companies,
            on: rc.id == r.related_company_id,
            join: t in assoc(r, :type),
            where:
              r.company_id == ^company_id and (^include_unlinked? or is_nil(r.deleted_at)) and
                is_nil(rc.deleted_at),
            preload: [type: t],
            select: {r, rc}
          )
          |> Repo.all()

        incoming =
          from(r in Relationship,
            join: c in ^scoped_companies,
            on: c.id == r.company_id,
            join: t in assoc(r, :type),
            where:
              r.related_company_id == ^company_id and (^include_unlinked? or is_nil(r.deleted_at)) and
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
      role_label:
        if(direction == :outgoing, do: r.type.name, else: RelationshipType.inverse_name(r.type)),
      other_company: Map.fetch!(summaries, other.id),
      effective_from: r.effective_from,
      effective_to: r.effective_to,
      unlinked_at: r.deleted_at,
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
            where: c.status != ^WritableCompany.archived_status(),
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

  # A relationship names two companies, and an archived one is read-only on
  # either side: creating refuses an archived owner (`:company_archived`) and
  # an archived related company (`:related_company_archived`), and updating or
  # deleting refuses either side being archived the same way.
  @spec create_relationship(Scope.t(), pos_integer(), map()) ::
          {:ok, Relationship.t()}
          | {:error,
             :forbidden
             | :company_not_found
             | :company_archived
             | :related_company_archived
             | Ecto.Changeset.t()}
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

    with :ok <- authorize_target(scope, company_id),
         {:ok, _company} <- WritableCompany.fetch_parent(scope, company_id) do
      if related_id != nil do
        case WritableCompany.fetch_parent(scope, related_id) do
          {:ok, _related} ->
            company_id
            |> create_changeset(attrs)
            |> Repo.insert()
            |> case do
              {:ok, rel} -> {:ok, Repo.preload(rel, [:type])}
              {:error, changeset} -> {:error, changeset}
            end

          {:error, :company_not_found} = error ->
            error

          {:error, :company_archived} ->
            {:error, :related_company_archived}
        end
      else
        company_id
        |> create_changeset(attrs)
        |> Repo.insert()
      end
    end
  end

  @spec update_relationship(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Relationship.t()}
          | {:error,
             :forbidden
             | :company_not_found
             | :company_archived
             | :related_company_archived
             | :not_found
             | Ecto.Changeset.t()}
  def update_relationship(%Scope{} = scope, company_id, relationship_id, attrs) do
    with :ok <- authorize_target(scope, company_id) do
      update_relationship_record(scope, company_id, relationship_id, attrs)
    end
  end

  defp update_relationship_record(%Scope{} = scope, company_id, relationship_id, attrs) do
    case WritableCompany.fetch_parent(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

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
            with :ok <- other_side_writable(scope, rel, company_id) do
              rel
              |> update_changeset(attrs)
              |> Repo.update()
            end
        end
    end
  end

  @spec delete_relationship(Scope.t(), pos_integer(), pos_integer()) ::
          :ok
          | {:error,
             :forbidden
             | :company_not_found
             | :company_archived
             | :related_company_archived
             | :not_found}
  def delete_relationship(%Scope{} = scope, company_id, relationship_id) do
    with :ok <- authorize_target(scope, company_id) do
      delete_relationship_record(scope, company_id, relationship_id)
    end
  end

  defp delete_relationship_record(%Scope{} = scope, company_id, relationship_id) do
    case WritableCompany.fetch_parent(scope, company_id) do
      {:error, reason} ->
        {:error, reason}

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
            with :ok <- other_side_writable(scope, rel, company_id) do
              case Repo.update(Ecto.Changeset.change(rel, %{deleted_at: now()})) do
                {:ok, _} -> :ok
                {:error, _} -> {:error, :not_found}
              end
            end
        end
    end
  end

  # The relationship is the other company's record too. A soft-deleted other
  # side no longer has a record to protect; an archived one does.
  defp other_side_writable(scope, %Relationship{} = rel, company_id) do
    other_id = if rel.company_id == company_id, do: rel.related_company_id, else: rel.company_id

    case WritableCompany.fetch_parent(scope, other_id) do
      {:error, :company_archived} -> {:error, :related_company_archived}
      _live_or_gone -> :ok
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

  @doc "Validates the same relationship rules without mutation; lifecycle previews are clock independent."
  def preview(scope, company_id, id, action, attrs) do
    with :ok <- authorize_target(scope, company_id),
         {:ok, _} <- WritableCompany.fetch_parent(scope, company_id) do
      if action == "create" do
        with {:ok, _} <- WritableCompany.fetch_parent(scope, attrs["related_company_id"]) do
          company_id
          |> create_changeset(attrs)
          |> preview_changes()
        end
      else
        with {:ok, rows} <- list_relationships(scope, company_id),
             %{relationship: row} <- Enum.find(rows, &(&1.id == id)),
             :ok <- other_side_writable(scope, row, company_id) do
          if action == "unlink" do
            {:ok,
             %{
               summary: "Unlink company relationship",
               changes: [%{field: "deleted_at", from: nil, to: "recorded at commit"}]
             }}
          else
            row |> update_changeset(attrs) |> preview_changes()
          end
        else
          nil -> {:error, :not_found}
          error -> error
        end
      end
    end
  end

  defp preview_changes(cs) do
    with {:ok, _} <- Ecto.Changeset.apply_action(cs, :validate) do
      {:ok,
       %{
         summary: "Change company relationship",
         changes:
           [%{field: "company_id", from: nil, to: cs.data.company_id}] ++
             Enum.map(cs.changes, fn {k, v} ->
               %{field: to_string(k), from: Map.get(cs.data, k), to: v}
             end)
       }}
    end
  end

  defp authorize_target(scope, company_id) do
    actor = Scope.actor(scope)

    if TenancyActor.system?(actor) and is_nil(TenancyActor.system_principal(actor)) do
      :ok
    else
      case Bilimbi.Core.Company.authorize_company_target(scope, company_id, @update_capability) do
        {:ok, _} -> :ok
        {:error, :unauthorized} -> {:error, :forbidden}
        {:error, :not_found} -> {:error, :company_not_found}
      end
    end
  end

  defp create_changeset(company_id, attrs) do
    %Relationship{company_id: company_id}
    |> Relationship.changeset(Map.drop(attrs, [:company_id, "company_id"]))
    |> validate_active_type()
    |> validate_no_open_duplicate()
  end

  defp validate_no_open_duplicate(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp validate_no_open_duplicate(cs) do
    open_ended? = is_nil(Ecto.Changeset.get_field(cs, :effective_to))

    live =
      from(r in Relationship,
        where:
          r.company_id == ^Ecto.Changeset.get_field(cs, :company_id) and
            r.related_company_id == ^Ecto.Changeset.get_field(cs, :related_company_id) and
            r.relationship_type_id == ^Ecto.Changeset.get_field(cs, :relationship_type_id) and
            is_nil(r.deleted_at) and is_nil(r.effective_to)
      )

    others = if cs.data.id, do: where(live, [r], r.id != ^cs.data.id), else: live
    duplicate? = open_ended? and Repo.exists?(others)

    if duplicate?,
      do:
        Ecto.Changeset.add_error(
          cs,
          :relationship_type_id,
          "is already assigned between these companies"
        ),
      else: cs
  end

  defp update_changeset(rel, attrs) do
    rel
    |> Relationship.update_changeset(attrs)
    |> validate_no_open_duplicate()
  end

  defp validate_active_type(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp validate_active_type(cs) do
    id = Ecto.Changeset.get_field(cs, :relationship_type_id)

    if Repo.exists?(from(t in RelationshipType, where: t.id == ^id and t.is_active)),
      do: cs,
      else: Ecto.Changeset.add_error(cs, :relationship_type_id, "is retired or unavailable")
  end

  defp now do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
