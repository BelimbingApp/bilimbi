defmodule Bilimbi.Core.Person do
  @moduledoc """
  Core person identity and company affiliation, independent of HR employment.

  This module owns person identity and affiliations; its schemas contain
  no employee number, employment type, HR status, dates or account identity.
  The retained employees API is a deprecated compatibility seam for People.
  A legacy_employee_id is an explicit migration mapping, never a person ID.
  Unlinking and retiring preserve records and never terminate employment or
  revoke access. Company relationships likewise confer no access.

  Reads are deliberately tenant-wide, like a shared address book: `list/2`,
  `get/2` and `affiliations/2` ask only `admin.person.list` or
  `admin.person.view`. Writes are company-authorized: every company a person
  is affiliated with must authorize the change. Do not narrow reads to the
  actor's companies to mirror Employee.
  """
  import Ecto.Query
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Person.{Schema, Affiliation}
  alias Ecto.Changeset

  def list(%Scope{} = scope, opts \\ []) do
    with :ok <- authorize(scope, "admin.person.list") do
      search = "%#{Keyword.get(opts, :search, "")}%"
      page = max(Keyword.get(opts, :page, 1), 1)
      size = min(max(Keyword.get(opts, :page_size, 25), 1), 100)

      withheld = Authz.restricted_fields(scope, "core_people")
      affiliation_withheld = Authz.restricted_fields(scope, "core_person_affiliations")
      email? = "email" not in withheld
      phone? = "phone" not in withheld
      affiliation_email? = "email" not in affiliation_withheld
      affiliation_phone? = "phone" not in affiliation_withheld

      matching_affiliations =
        from(a in Tenancy.scope_query(Affiliation, scope),
          where: is_nil(a.unlinked_at),
          where:
            (^affiliation_email? and ilike(a.email, ^search)) or
              (^affiliation_phone? and ilike(a.phone, ^search)),
          select: a.person_id
        )

      query =
        from(p in Tenancy.scope_query(Schema, scope),
          where: is_nil(p.retired_at),
          where:
            ilike(p.full_name, ^search) or (^email? and ilike(p.email, ^search)) or
              (^phone? and ilike(p.phone, ^search)) or p.id in subquery(matching_affiliations)
        )

      total = Repo.aggregate(query, :count)

      rows =
        Repo.all(
          from(p in query,
            order_by: [asc: p.full_name, asc: p.id],
            limit: ^size,
            offset: ^((page - 1) * size)
          )
        )

      {:ok,
       %{entries: Enum.map(rows, &summary(&1, scope)), total: total, page: page, page_size: size}}
    end
  end

  def get(%Scope{} = scope, id) do
    with :ok <- authorize(scope, "admin.person.view"),
         {:ok, person} <- fetch(scope, id),
         {:ok, affiliations} <- affiliations(scope, id) do
      {:ok, Map.put(summary(person, scope), :affiliations, affiliations)}
    end
  end

  def affiliations(%Scope{} = scope, person_id) do
    with :ok <- authorize(scope, "admin.person.view"), {:ok, _} <- fetch(scope, person_id) do
      rows =
        Repo.all(
          from(a in Tenancy.scope_query(Affiliation, scope),
            where: a.person_id == ^person_id,
            order_by: [asc: a.id]
          )
        )

      {:ok,
       Enum.map(rows, fn row ->
         company_name =
           case Company.identity(scope, row.company_id) do
             {:ok, company} -> company.display_name
             {:error, _} -> "Company unavailable"
           end

         Map.put(summary(row, scope), :company_name, company_name)
       end)}
    end
  end

  @doc "The scoped compatibility mapping for an existing Employee ID. It is never a login or HR grant."
  def legacy_affiliation(%Scope{} = scope, employee_id) do
    with :ok <- authorize(scope, "admin.person.view") do
      case Repo.one(
             from(a in Tenancy.scope_query(Affiliation, scope),
               where: a.legacy_employee_id == ^employee_id
             )
           ) do
        nil -> {:error, :not_found}
        row -> {:ok, summary(row, scope)}
      end
    end
  end

  def create(%Scope{} = scope, attrs) do
    with {:ok, changeset} <- person_changeset(scope, nil, attrs, "admin.person.create") do
      persist(changeset, :insert, scope)
    end
  end

  @doc """
  The live affiliation companies a person-wide change reaches, after the actor
  is authorized for each of them. Updating or retiring a person changes what
  every affiliated company sees, so one unauthorized company refuses it.
  """
  def person_targets(%Scope{} = scope, person_id) do
    with :ok <- authorize(scope, "admin.person.update"),
         {:ok, person} <- fetch(scope, person_id),
         :ok <- live(person),
         do: authorize_affiliated_companies(scope, person.id)
  end

  def update(%Scope{} = scope, id, attrs) do
    with {:ok, changeset} <- person_changeset(scope, id, attrs, "admin.person.update") do
      persist(changeset, :update, scope)
    end
  end

  def retire(%Scope{} = scope, id) do
    with {:ok, changeset} <- person_changeset(scope, id, %{}, "admin.person.update") do
      persist(Changeset.change(changeset, retired_at: now()), :update, scope)
    end
  end

  # A namecard is one transaction: identity plus the supplied company contact
  # facts. Reusing a person is explicit; matching names or email never merges
  # unrelated people automatically.
  def create_contact(%Scope{} = scope, company_id, attrs) do
    with {:ok, _} <- target(scope, company_id, "admin.person.create"),
         {:ok, person_cs} <- person_changeset(scope, nil, attrs, "admin.person.create") do
      Bilimbi.Base.Audit.with_scope(scope, fn ->
        Repo.transaction(fn ->
          lock_company_or_rollback(scope, company_id)
          person = insert_or_rollback(person_cs)

          affiliation =
            %Affiliation{tenant_id: scope.tenant.id, person_id: person.id, company_id: company_id}
            |> Affiliation.changeset(attrs)
            |> Authz.refuse_restricted_attempts(scope, "core_person_affiliations", attrs)
            |> insert_or_rollback()

          %{person: summary(person, scope), affiliation: summary(affiliation, scope)}
        end)
      end)
    end
  end

  def link(%Scope{} = scope, person_id, company_id, attrs) do
    with {:ok, cs} <- affiliation_changeset(scope, person_id, company_id, nil, attrs) do
      persist(cs, :insert, scope)
    end
  end

  def update_affiliation(%Scope{} = scope, person_id, id, attrs) do
    with {:ok, cs} <- affiliation_changeset(scope, person_id, nil, id, attrs) do
      persist(cs, :update, scope)
    end
  end

  @doc "Authorizes a contact company's target before an agent consults its write policy."
  def company_target(%Scope{} = scope, company_id, capability) do
    with :ok <- authorize(scope, capability),
         {:ok, company} <- target(scope, company_id, capability),
         do: {:ok, company.id}
  end

  @doc "Resolves the validated company target for an affiliation write; never changes the actor's company."
  def affiliation_target(%Scope{} = scope, person_id, id) do
    with :ok <- authorize(scope, "admin.person.update"),
         {:ok, affiliation} <- fetch_affiliation(scope, person_id, nil, id),
         {:ok, _} <- target(scope, affiliation.company_id, "admin.person.update"),
         do: {:ok, affiliation.company_id}
  end

  def unlink(%Scope{} = scope, person_id, id) do
    with {:ok, cs} <- affiliation_changeset(scope, person_id, nil, id, %{}) do
      persist(Changeset.change(cs, unlinked_at: now()), :update, scope)
    end
  end

  def preview(%Scope{} = scope, action, input) do
    case action do
      :create ->
        preview_person(scope, nil, input, "admin.person.create")

      :update ->
        preview_person(scope, input["person_id"], input, "admin.person.update")

      :retire ->
        with {:ok, cs} <- person_changeset(scope, input["person_id"], %{}, "admin.person.update"),
             do: preview_changes(Changeset.change(cs, retired_at: now()), :retired_at)

      :contact ->
        with {:ok, _} <- target(scope, input["company_id"], "admin.person.create"),
             {:ok, person_cs} <- person_changeset(scope, nil, input, "admin.person.create"),
             {:ok, _} <- Changeset.apply_action(person_cs, :insert),
             affiliation_cs =
               Affiliation.changeset(
                 %Affiliation{
                   tenant_id: scope.tenant.id,
                   person_id: 1,
                   company_id: input["company_id"]
                 },
                 input
               )
               |> Authz.refuse_restricted_attempts(scope, "core_person_affiliations", input),
             {:ok, _} <- Changeset.apply_action(affiliation_cs, :insert) do
          {:ok,
           %{
             summary: "Create contact and company affiliation",
             changes:
               [%{field: "company_id", from: nil, to: input["company_id"]}] ++
                 changes(person_cs) ++
                 Enum.filter(
                   changes(affiliation_cs),
                   &(&1.field in ~w(title email phone company_id))
                 )
           }}
        end

      action when action in [:link, :affiliation_update, :unlink] ->
        with {:ok, cs} <-
               affiliation_changeset(
                 scope,
                 input["person_id"],
                 input["company_id"],
                 input["affiliation_id"],
                 input
               ) do
          cs = if action == :unlink, do: Changeset.change(cs, unlinked_at: now()), else: cs
          preview_changes(cs, if(action == :unlink, do: :unlinked_at, else: nil))
        end
    end
  end

  defp preview_person(scope, id, attrs, capability) do
    with {:ok, cs} <- person_changeset(scope, id, attrs, capability), do: preview_changes(cs)
  end

  defp person_changeset(scope, id, attrs, capability) do
    with :ok <- authorize(scope, capability),
         :ok <- reject_hr(attrs),
         {:ok, person} <-
           if(is_nil(id), do: {:ok, %Schema{tenant_id: scope.tenant.id}}, else: fetch(scope, id)),
         :ok <- live(person),
         {:ok, _} <-
           if(is_nil(id), do: {:ok, []}, else: authorize_affiliated_companies(scope, id)) do
      {:ok,
       Schema.changeset(person, attrs)
       |> Authz.refuse_restricted_attempts(scope, "core_people", attrs)}
    end
  end

  defp authorize_affiliated_companies(scope, person_id) do
    company_ids =
      Repo.all(
        from(a in Tenancy.scope_query(Affiliation, scope),
          where: a.person_id == ^person_id and is_nil(a.unlinked_at),
          distinct: true,
          order_by: a.company_id,
          select: a.company_id
        )
      )

    system? =
      Actor.system?(Scope.actor(scope)) and is_nil(Actor.system_principal(Scope.actor(scope)))

    Enum.reduce_while(company_ids, {:ok, company_ids}, fn company_id, ok ->
      with false <- system?,
           {:error, reason} when reason != :not_found <-
             Company.authorize_company_target(scope, company_id, "admin.person.update") do
        {:halt, {:error, reason}}
      else
        _ -> {:cont, ok}
      end
    end)
  end

  defp affiliation_changeset(scope, person_id, company_id, id, attrs) do
    with :ok <- authorize(scope, "admin.person.update"),
         :ok <- reject_hr(attrs),
         {:ok, person} <- fetch(scope, person_id),
         :ok <- live(person),
         {:ok, affiliation} <- fetch_affiliation(scope, person_id, company_id, id),
         {:ok, _} <- target(scope, affiliation.company_id, "admin.person.update") do
      if affiliation.unlinked_at,
        do: {:error, :affiliation_unlinked},
        else:
          {:ok,
           Affiliation.changeset(affiliation, attrs)
           |> Authz.refuse_restricted_attempts(scope, "core_person_affiliations", attrs)}
    end
  end

  defp fetch_affiliation(scope, person_id, company_id, nil),
    do:
      {:ok,
       %Affiliation{tenant_id: scope.tenant.id, person_id: person_id, company_id: company_id}}

  defp fetch_affiliation(scope, person_id, _company_id, id) do
    case Repo.one(
           from(a in Tenancy.scope_query(Affiliation, scope),
             where: a.id == ^id and a.person_id == ^person_id
           )
         ) do
      nil -> {:error, :not_found}
      a -> {:ok, a}
    end
  end

  defp fetch(scope, id, lock \\ false) do
    query = from(p in Tenancy.scope_query(Schema, scope), where: p.id == ^id)
    query = if lock, do: from(p in query, lock: "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :not_found}
      person -> {:ok, person}
    end
  end

  defp target(scope, id, capability) do
    actor = Scope.actor(scope)

    if Actor.system?(actor) and is_nil(Actor.system_principal(actor)) do
      Company.require_writable_company(scope, id)
    else
      with {:ok, company} <- Company.authorize_company_target(scope, id, capability),
           {:ok, _} <- Company.require_writable_company(scope, id),
           do: {:ok, company}
    end
  end

  defp authorize(scope, capability) do
    actor = Scope.actor(scope)

    if Actor.system?(actor) and is_nil(Actor.system_principal(actor)),
      do: :ok,
      else: if(Authz.can(scope, capability).allowed, do: :ok, else: {:error, :forbidden})
  end

  defp live(%Schema{retired_at: nil}), do: :ok
  defp live(_), do: {:error, :person_retired}

  defp reject_hr(attrs) do
    fields =
      ~w(employee_number employee_type status employment_start employment_end department_id supervisor_id job_description user_id)

    if Enum.any?(fields, fn key ->
         Map.has_key?(attrs, key) or Enum.any?(Map.keys(attrs), &(to_string(&1) == key))
       end), do: {:error, :hr_fields_not_supported}, else: :ok
  end

  defp persist(%Changeset{valid?: false} = cs, operation, _scope),
    do: {:error, %{cs | action: operation}}

  defp persist(cs, operation, scope) do
    Bilimbi.Base.Audit.with_scope(scope, fn ->
      Repo.transaction(fn ->
        cs = lock_changeset(scope, cs, operation)

        case apply(Repo, operation, [cs]) do
          {:ok, row} -> summary(row, scope)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  # Company -> Person -> affiliation is the lock order. In particular a
  # company cannot be archived between validating a target and inserting its
  # contact, and retirement/unlink cannot race a later contact edit.
  defp lock_changeset(scope, %Changeset{data: %Affiliation{} = row} = cs, _operation) do
    lock_company_or_rollback(scope, row.company_id)
    _ = lock_person_or_rollback(scope, row.person_id)

    if row.id do
      current =
        Repo.one(
          from(a in Tenancy.scope_query(Affiliation, scope),
            where: a.id == ^row.id and a.person_id == ^row.person_id,
            lock: "FOR UPDATE"
          )
        )

      cond do
        is_nil(current) -> Repo.rollback(:not_found)
        current.unlinked_at -> Repo.rollback(:affiliation_unlinked)
        true -> %{cs | data: current}
      end
    else
      cs
    end
  end

  defp lock_changeset(scope, %Changeset{data: %Schema{id: id}} = cs, :update) do
    person = lock_person_or_rollback(scope, id)

    case authorize_affiliated_companies(scope, id) do
      {:ok, _} -> %{cs | data: person}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_changeset(_scope, cs, :insert), do: cs

  defp lock_person_or_rollback(scope, id) do
    with {:ok, person} <- fetch(scope, id, true), :ok <- live(person) do
      person
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_company_or_rollback(scope, id) do
    case Company.lock_writable_company(scope, id) do
      {:ok, proof} -> proof
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert_or_rollback(cs) do
    case Repo.insert(cs) do
      {:ok, row} -> row
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp preview_changes(cs, lifecycle_field \\ nil) do
    targets =
      if match?(%Affiliation{}, cs.data),
        do:
          Enum.map([:person_id, :company_id], fn field ->
            %{field: to_string(field), from: nil, to: Map.fetch!(cs.data, field)}
          end),
        else: []

    with {:ok, _} <- Changeset.apply_action(cs, :validate),
         do:
           {:ok,
            %{
              summary: "Change person or affiliation",
              changes:
                targets ++
                  Enum.map(changes(cs), fn c ->
                    if c.field == to_string(lifecycle_field),
                      do: %{c | to: "recorded at commit"},
                      else: c
                  end)
            }}
  end

  defp changes(cs) do
    cs.changes
    |> Enum.sort()
    |> Enum.map(fn {field, value} ->
      %{field: Atom.to_string(field), from: Map.get(cs.data, field), to: value}
    end)
  end

  defp summary(row, scope) do
    table = if match?(%Schema{}, row), do: "core_people", else: "core_person_affiliations"
    Authz.redact(scope, table, row |> Map.from_struct() |> Map.drop([:__meta__, :tenant_id]))
  end

  @doc "Operational refusal wording shared by the contact adapters."
  def refusal_message(%Changeset{} = cs),
    do:
      cs.errors
      |> Enum.map(fn {field, {message, _}} -> "#{field} #{message}" end)
      |> Enum.join(", ")

  def refusal_message(reason) do
    case reason do
      :forbidden ->
        "You do not have permission to change contacts."

      :unauthorized ->
        "You do not have permission to work with this company."

      :not_found ->
        "The contact or company is not in this tenant."

      :company_not_found ->
        "The company is not in this tenant."

      :company_archived ->
        "The company is archived and read-only."

      :person_retired ->
        "The contact is retired and read-only."

      :affiliation_unlinked ->
        "The affiliation has already been unlinked."

      :hr_fields_not_supported ->
        "Employment facts belong to People; only identity and affiliation facts are accepted."

      _ ->
        "The change was refused. Refresh the record and try again."
    end
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
