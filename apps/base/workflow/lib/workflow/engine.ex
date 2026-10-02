defmodule Bilimbi.Base.Workflow.Engine do
  @moduledoc false
  import Ecto.Query

  alias Bilimbi.Base.{Audit, Authz, Repo, Tenancy}
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.{BindingSchema, Definitions, HistorySchema, JSON, Subject}

  def transition(scope, ref, to, context) do
    Scope.actor(scope)

    with {:ok, ref} <- Definitions.subject(ref),
         {:ok, context} <- context(context) do
      attributed(scope, fn ->
        Repo.transact(fn ->
          with :ok <- writer(scope),
               {:ok, subject} <- load(scope, ref, :lock, :transition),
               {:ok, _flow} <- Definitions.flow(ref, :lock),
               {:ok, edge} <- edge(ref, subject.status, to),
               :ok <- capability(scope, ref, subject, edge.capability),
               :ok <- hook(:guards, edge.guard, scope, subject, edge, context),
               :ok <- bind(scope, ref),
               :ok <- ref.adapter.persist(scope, subject, to, context),
               :ok <- hook(:actions, edge.action, scope, %{subject | status: to}, edge, context),
               {:ok, persisted} <- load(scope, ref, :read, :transition),
               true <- persisted.status == to,
               {:ok, history} <- append(scope, ref, subject, to, :transition, context),
               {:ok, _action} <- audit(scope, ref, subject, to, history.id, :transition) do
            {:ok,
             %{
               subject: %{type: ref.type, id: ref.id},
               from: subject.status,
               to: to,
               history: fact(history)
             }}
          else
            false -> {:error, :invalid_adapter_status}
            {:error, _} = error -> error
          end
        end)
      end)
    end
  end

  def record(scope, ref, kind, context) do
    Scope.actor(scope)

    with {:ok, ref} <- Definitions.subject(ref), {:ok, context} <- context(context) do
      attributed(scope, fn ->
        Repo.transact(fn ->
          with :ok <- writer(scope),
               {:ok, subject} <- load(scope, ref, :lock, kind),
               {:ok, _flow} <- Definitions.flow(ref, :lock),
               :ok <- record_allowed(ref, subject, kind, context),
               :ok <- bind(scope, ref),
               {:ok, history} <- append(scope, ref, subject, subject.status, kind, context),
               {:ok, _action} <- audit(scope, ref, subject, subject.status, history.id, kind) do
            {:ok, fact(history)}
          end
        end)
      end)
    end
  end

  def adopt(scope, ref) do
    Scope.actor(scope)

    with {:ok, ref} <- Definitions.subject(ref) do
      attributed(scope, fn ->
        Repo.transact(fn ->
          with :ok <- writer(scope),
               {:ok, _subject} <- load(scope, ref, :lock, :adopt),
               {:ok, _flow} <- Definitions.flow(ref, :adopt),
               :ok <- bind(scope, ref) do
            {:ok, %{type: ref.type, id: ref.id, flow: ref.flow}}
          end
        end)
      end)
    end
  end

  def available(scope, ref) do
    Scope.actor(scope)

    with {:ok, ref} <- Definitions.subject(ref),
         {:ok, subject} <- load(scope, ref, :read, :read),
         {:ok, _flow} <- Definitions.flow(ref, :read) do
      candidates =
        if Definitions.status?(ref.flow, subject.status, :read),
          do: Definitions.edges(ref.flow, subject.status, :read),
          else: []

      edges =
        Enum.flat_map(candidates, fn stored ->
          with {:ok, edge} <- normalize_edge(ref, stored),
               true <- Definitions.status?(ref.flow, edge.to, :read),
               :ok <- capability(scope, ref, subject, edge.capability) do
            [Map.drop(edge, [:guard, :action])]
          else
            _ -> []
          end
        end)

      {:ok, edges}
    end
  end

  def history(scope, ref, opts) do
    Scope.actor(scope)
    opts = Keyword.validate!(opts, limit: 50, after: nil)
    limit = opts[:limit]

    unless is_integer(limit) and limit in 1..500,
      do: raise(ArgumentError, "history limit must be 1..500")

    with {:ok, ref} <- Definitions.subject(ref),
         {:ok, _subject} <- load(scope, ref, :read, :read) do
      query =
        from b in Tenancy.scope_query(BindingSchema, scope),
          join: h in HistorySchema,
          on: h.flow == b.flow and h.flow_id == b.flow_id,
          where:
            b.subject_type == ^ref.type and b.subject_id == ^to_string(ref.id) and
              b.owner == ^ref.owner,
          order_by: [asc: h.transitioned_at, asc: h.id],
          limit: ^(limit + 1),
          select: h

      query = cursor(query, opts[:after])
      rows = Repo.all(query)
      page = Enum.take(rows, limit)

      next =
        if length(rows) > limit, do: page |> List.last() |> then(&{&1.transitioned_at, &1.id})

      {:ok, %{entries: Enum.map(page, &fact/1), next_cursor: next}}
    end
  end

  defp cursor(query, nil), do: query

  defp cursor(query, {%NaiveDateTime{} = time, id}) when is_integer(id) and id > 0,
    do:
      from([_b, h] in query,
        where: h.transitioned_at > ^time or (h.transitioned_at == ^time and h.id > ^id)
      )

  defp cursor(_query, _cursor), do: raise(ArgumentError, "invalid history cursor")

  defp load(scope, ref, mode, operation) do
    with {:ok, %Subject{} = subject} <- ref.adapter.load(scope, ref.id, mode),
         true <- subject.id == ref.id and subject.tenant_id == Scope.tenant_id(scope),
         true <- is_binary(subject.status) and subject.status != "",
         true <- match?({:ok, _}, JSON.cast(subject.facts)),
         :ok <- ref.adapter.authorize(scope, subject, operation) do
      {:ok, subject}
    else
      false -> {:error, :invalid_adapter_subject}
      {:error, _} = error -> error
      _ -> {:error, :invalid_adapter_subject}
    end
  end

  defp writer(scope) do
    case Scope.actor(scope) do
      %{type: :user} -> :ok
      %{type: :system, system_principal: name} when is_binary(name) -> :ok
      _ -> {:error, :no_authenticated_actor}
    end
  end

  defp edge(ref, from, to) do
    stored = Enum.find(Definitions.edges(ref.flow, from, :lock), &(&1.to_code == to))

    with true <- not is_nil(stored),
         true <-
           Definitions.status?(ref.flow, from, :lock) and Definitions.status?(ref.flow, to, :lock),
         {:ok, edge} <- normalize_edge(ref, stored) do
      {:ok, edge}
    else
      false -> {:error, :invalid_edge}
      {:error, _} = error -> error
    end
  end

  defp normalize_edge(ref, stored) do
    with {:ok, guard} <- Definitions.hook(:guards, stored.guard_class, ref.owner),
         {:ok, action} <- Definitions.hook(:actions, stored.action_class, ref.owner) do
      {:ok,
       %{
         from: stored.from_code,
         to: stored.to_code,
         label: stored.label,
         capability: stored.capability,
         guard: guard,
         action: action,
         sla_seconds: stored.sla_seconds,
         metadata: stored.metadata
       }}
    end
  end

  defp capability(_scope, _ref, _subject, nil), do: :ok

  defp capability(scope, ref, subject, capability) do
    resource = Resource.new!(ref.type, ref.id, scope: scope, company_id: subject.company_id)

    if Authz.can(scope, capability, resource).allowed,
      do: :ok,
      else: {:error, :missing_capability}
  end

  defp hook(kind, nil, _scope, _subject, _edge, _context) when kind in [:guards, :actions],
    do: :ok

  defp hook(:guards, hook, scope, subject, edge, context),
    do: hook.adapter.check(scope, subject, public_edge(edge), context)

  defp hook(:actions, hook, scope, subject, edge, context),
    do: hook.adapter.execute(scope, subject, public_edge(edge), context)

  defp public_edge(edge),
    do: Map.update!(Map.update!(edge, :guard, &(&1 && &1.key)), :action, &(&1 && &1.key))

  # The global uniqueness proof deliberately reads the owned binding across
  # tenants after owner row locking. A scope-filtered miss must never allow
  # the same legacy (flow, flow_id) to be rebound to another tenant.
  defp bind(scope, ref) do
    attrs = %{
      tenant_id: Scope.tenant_id(scope),
      flow: ref.flow,
      flow_id: ref.id,
      subject_type: ref.type,
      subject_id: to_string(ref.id),
      owner: ref.owner,
      created_at: now()
    }

    Repo.insert_all(BindingSchema, [attrs], on_conflict: :nothing)

    binding =
      Repo.one(
        from b in BindingSchema,
          where: b.flow == ^ref.flow and b.flow_id == ^ref.id,
          lock: "FOR UPDATE"
      )

    case binding do
      %{tenant_id: tenant_id, subject_type: type, subject_id: id, owner: owner}
      when tenant_id == attrs.tenant_id and type == ref.type and id == attrs.subject_id and
             owner == ref.owner ->
        :ok

      _ ->
        {:error, :subject_binding_conflict}
    end
  end

  defp record_allowed(ref, subject, :record_initial, _context) do
    cond do
      not Definitions.status?(ref.flow, subject.status, :lock) -> {:error, :invalid_status}
      not is_nil(latest(ref)) -> {:error, :history_exists}
      true -> :ok
    end
  end

  defp record_allowed(_ref, _subject, :record_comment, %{comment: comment})
       when is_binary(comment) and comment != "", do: :ok

  defp record_allowed(_ref, _subject, :record_comment, _context), do: {:error, :comment_required}

  defp latest(ref), do: Repo.one(latest_query(ref))

  defp tat_anchor(ref),
    do:
      Repo.one(
        from h in latest_query(ref),
          where:
            fragment("(?->'_workflow'->>'kind') IS DISTINCT FROM 'record_comment'", h.metadata)
      )

  defp latest_query(ref) do
    from h in HistorySchema,
      where: h.flow == ^ref.flow and h.flow_id == ^ref.id,
      order_by: [desc: h.transitioned_at, desc: h.id],
      limit: 1
  end

  defp append(scope, ref, subject, status, kind, context) do
    actor = Scope.actor(scope)
    time = now()
    previous = if kind == :transition, do: tat_anchor(ref)
    tat = if previous, do: max(0, NaiveDateTime.diff(time, previous.transitioned_at))

    provenance = %{
      "subject_type" => ref.type,
      "kind" => Atom.to_string(kind),
      "from_status" => subject.status,
      "impersonator_id" => actor.impersonator_id,
      "system_principal" => actor.system_principal
    }

    attrs =
      Map.take(context, [:comment, :comment_tag, :assignees, :attachments])
      |> Map.merge(%{
        flow: ref.flow,
        flow_id: ref.id,
        status: status,
        tat: tat,
        actor_type: Atom.to_string(actor.type),
        actor_id: actor.user_id,
        metadata: Map.put(context.metadata, "_workflow", provenance),
        transitioned_at: time,
        created_at: time
      })

    %HistorySchema{} |> Ecto.Changeset.change(attrs) |> Repo.insert()
  end

  defp audit(scope, ref, subject, to, history_id, kind) do
    actor = Scope.actor(scope)

    Audit.record_action(scope, %{
      event: event(kind),
      occurred_at: now(),
      actor_type: Atom.to_string(actor.type),
      actor_id: actor.user_id || 0,
      company_id: subject.company_id,
      impersonator_id: actor.impersonator_id,
      system_principal: actor.system_principal,
      payload: %{
        "subject_type" => ref.type,
        "subject_id" => to_string(ref.id),
        "flow" => ref.flow,
        "from_status" => subject.status,
        "to_status" => to,
        "history_id" => history_id
      }
    })
  end

  defp event(:transition), do: "workflow.transition.completed"
  defp event(:record_initial), do: "workflow.history.initial_recorded"
  defp event(:record_comment), do: "workflow.history.comment_recorded"

  defp context(context) when is_map(context) and not is_struct(context) do
    allowed = [:comment, :comment_tag, :assignees, :attachments, :metadata, :input]
    metadata = Map.get(context, :metadata, %{})

    text? =
      Enum.all?([:comment, :comment_tag], fn key ->
        is_nil(context[key]) or is_binary(context[key])
      end)

    if Map.keys(context) -- allowed == [] and text? and is_map(metadata) and
         not Map.has_key?(metadata, "_workflow") and
         Enum.all?(
           [:metadata, :input, :assignees, :attachments],
           &match?({:ok, _}, JSON.cast(Map.get(context, &1)))
         ) do
      {:ok, Map.merge(%{metadata: %{}, input: %{}}, context)}
    else
      {:error, :invalid_context}
    end
  end

  defp context(_context), do: {:error, :invalid_context}

  defp attributed(scope, fun) do
    previous = AuditContext.get()
    actor = Scope.actor(scope)

    AuditContext.put(%{
      previous
      | tenant_id: Scope.tenant_id(scope),
        company_id: actor.company_id,
        actor_type: Atom.to_string(actor.type),
        actor_id: actor.user_id || 0,
        impersonator_id: actor.impersonator_id,
        system_principal: actor.system_principal
    })

    try do
      fun.()
    after
      AuditContext.put(previous)
    end
  end

  defp fact(history), do: history |> Map.from_struct() |> Map.delete(:__meta__)
  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
