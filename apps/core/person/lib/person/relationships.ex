defmodule Bilimbi.Core.Person.Relationships do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Person
  alias Bilimbi.Core.Person.Relationship
  alias Ecto.Changeset

  @table "core_person_relationships"
  @update "admin.person.update"

  def list(%Scope{} = scope, person_id, opts \\ []) do
    with :ok <- Person.authorize(scope, "admin.person.view"),
         {:ok, _} <- Person.fetch(scope, person_id) do
      include_unlinked? = Keyword.get(opts, :include_unlinked, false) == true
      {:ok, types} = Company.list_relationship_types()
      types = Map.new(types, &{&1.id, &1})

      rows =
        Repo.all(
          from(r in Tenancy.scope_query(Relationship, scope),
            where: r.person_id == ^person_id and (^include_unlinked? or is_nil(r.deleted_at)),
            order_by: [asc: r.id]
          )
        )

      {:ok, Enum.map(rows, &read_model(&1, Map.fetch!(types, &1.relationship_type_id), scope))}
    end
  end

  def target(%Scope{} = scope, person_id, id) do
    with :ok <- Person.authorize(scope, @update),
         {:ok, row} <- fetch_row(scope, person_id, nil, id),
         {:ok, _} <- Person.target(scope, row.company_id, @update),
         do: {:ok, row.company_id}
  end

  def create(%Scope{} = scope, person_id, company_id, attrs) do
    with {:ok, cs} <- changeset(scope, person_id, company_id, nil, attrs),
         do: persist(scope, cs, :insert)
  end

  def update(%Scope{} = scope, person_id, id, attrs) do
    with {:ok, cs} <- changeset(scope, person_id, nil, id, attrs),
         do: persist(scope, cs, :update)
  end

  def end_role(%Scope{} = scope, person_id, id, attrs),
    do: update(scope, person_id, id, ending_attrs(attrs))

  @doc false
  def ending_attrs(attrs) do
    case Map.get(attrs, "effective_to") || Map.get(attrs, :effective_to) do
      blank when blank in [nil, ""] -> %{"effective_to" => Date.to_iso8601(Date.utc_today())}
      date -> %{"effective_to" => date}
    end
  end

  def unlink(%Scope{} = scope, person_id, id) do
    with {:ok, cs} <- changeset(scope, person_id, nil, id, %{}),
         do: persist(scope, Changeset.change(cs, deleted_at: now()), :update)
  end

  def preview(%Scope{} = scope, action, input) do
    id = if action == :relationship_create, do: nil, else: input["relationship_id"]
    attrs = if action == :relationship_end, do: ending_attrs(input), else: input

    with {:ok, cs} <- changeset(scope, input["person_id"], input["company_id"], id, attrs),
         cs =
           if(action == :relationship_unlink,
             do: Changeset.change(cs, deleted_at: now()),
             else: cs
           ),
         {:ok, _} <- Changeset.apply_action(cs, :validate) do
      {:ok,
       %{
         summary: "Change person role",
         changes:
           Enum.map([:person_id, :company_id], fn field ->
             %{field: to_string(field), from: nil, to: Map.fetch!(cs.data, field)}
           end) ++
             Enum.map(Enum.sort(cs.changes), fn {field, value} ->
               %{
                 field: Atom.to_string(field),
                 from: Map.get(cs.data, field),
                 to: if(field == :deleted_at, do: "recorded at commit", else: value)
               }
             end)
       }}
    end
  end

  defp changeset(scope, person_id, company_id, id, attrs) do
    with :ok <- Person.authorize(scope, @update),
         {:ok, person} <- Person.fetch(scope, person_id),
         :ok <- Person.live(person),
         {:ok, row} <- fetch_row(scope, person_id, company_id, id),
         {:ok, _} <- target_company(scope, row.company_id) do
      if row.deleted_at do
        {:error, :relationship_unlinked}
      else
        cs =
          if id,
            do: Relationship.update_changeset(row, attrs),
            else: row |> Relationship.changeset(attrs) |> validate_active_type()

        {:ok,
         cs
         |> validate_no_open_duplicate(scope)
         |> Authz.refuse_restricted_attempts(scope, @table, attrs)}
      end
    end
  end

  defp target_company(scope, company_id) when is_integer(company_id),
    do: Person.target(scope, company_id, @update)

  defp target_company(_scope, _company_id), do: {:error, :company_not_found}

  defp fetch_row(scope, person_id, company_id, nil),
    do:
      {:ok,
       %Relationship{tenant_id: scope.tenant.id, person_id: person_id, company_id: company_id}}

  defp fetch_row(scope, person_id, _company_id, id) do
    case Repo.one(
           from(r in Tenancy.scope_query(Relationship, scope),
             where: r.id == ^id and r.person_id == ^person_id
           )
         ) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  defp validate_active_type(%Changeset{valid?: false} = cs), do: cs

  defp validate_active_type(cs) do
    case Company.get_relationship_type(Changeset.get_field(cs, :relationship_type_id)) do
      {:ok, %{is_active: true}} ->
        cs

      _ ->
        Changeset.add_error(cs, :relationship_type_id, "is retired or unavailable")
    end
  end

  defp validate_no_open_duplicate(%Changeset{valid?: false} = cs, _scope), do: cs

  defp validate_no_open_duplicate(cs, scope) do
    live =
      from(r in Tenancy.scope_query(Relationship, scope),
        where:
          r.company_id == ^Changeset.get_field(cs, :company_id) and
            r.person_id == ^Changeset.get_field(cs, :person_id) and
            r.relationship_type_id == ^Changeset.get_field(cs, :relationship_type_id) and
            is_nil(r.deleted_at) and is_nil(r.effective_to)
      )

    others = if cs.data.id, do: where(live, [r], r.id != ^cs.data.id), else: live

    if is_nil(Changeset.get_field(cs, :effective_to)) and Repo.exists?(others),
      do:
        Changeset.add_error(
          cs,
          if(cs.data.id, do: :effective_to, else: :relationship_type_id),
          Relationship.live_duplicate_message()
        ),
      else: cs
  end

  # Company -> Person -> role is the lock order, like affiliations: a company
  # cannot be archived, nor a person retired, between validating a target and
  # writing the role.
  defp persist(_scope, %Changeset{valid?: false} = cs, operation),
    do: {:error, %{cs | action: operation}}

  defp persist(scope, %Changeset{data: row} = cs, operation) do
    Bilimbi.Base.Audit.with_scope(scope, fn ->
      Repo.transaction(fn ->
        Person.lock_company_or_rollback(scope, row.company_id)
        _ = Person.lock_person_or_rollback(scope, row.person_id)
        cs = lock_row(scope, cs)

        case apply(Repo, operation, [cs]) do
          {:ok, saved} -> saved_model(saved, scope)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  defp lock_row(_scope, %Changeset{data: %Relationship{id: nil}} = cs), do: cs

  defp lock_row(scope, %Changeset{data: row} = cs) do
    current =
      Repo.one(
        from(r in Tenancy.scope_query(Relationship, scope),
          where: r.id == ^row.id and r.person_id == ^row.person_id,
          lock: "FOR UPDATE"
        )
      )

    cond do
      is_nil(current) -> Repo.rollback(:not_found)
      current.deleted_at -> Repo.rollback(:relationship_unlinked)
      true -> %{cs | data: current}
    end
  end

  defp saved_model(row, scope) do
    {:ok, type} = Company.get_relationship_type(row.relationship_type_id)
    read_model(row, type, scope)
  end

  defp read_model(row, type, scope) do
    company_name =
      case Company.identity(scope, row.company_id) do
        {:ok, company} -> company.display_name
        {:error, _} -> "Company unavailable"
      end

    today = Date.utc_today()

    Authz.redact(scope, @table, %{
      id: row.id,
      person_id: row.person_id,
      company_id: row.company_id,
      company_name: company_name,
      relationship_type_id: row.relationship_type_id,
      role_code: type.code,
      role_label: type.name,
      inverse_label: type.inverse_name,
      effective_from: row.effective_from,
      effective_to: row.effective_to,
      unlinked_at: row.deleted_at,
      is_active:
        is_nil(row.deleted_at) and
          (is_nil(row.effective_from) or Date.compare(row.effective_from, today) != :gt) and
          (is_nil(row.effective_to) or Date.compare(row.effective_to, today) != :lt)
    })
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
