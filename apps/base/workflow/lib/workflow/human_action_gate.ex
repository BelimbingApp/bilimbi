defmodule Bilimbi.Base.Workflow.HumanActionGate do
  @moduledoc false
  import Ecto.Query
  alias Bilimbi.Base.{Audit, Authz, Repo, Tenancy}
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Tenancy.Scope

  alias Bilimbi.Base.Workflow.{
    Attribution,
    Coordination,
    Definitions,
    IntentDigest,
    JSON,
    PendingWork,
    RequestSchema,
    Subject
  }

  @request_keys [
    :action_key,
    :idempotency_key,
    :expected_subject_version,
    :payload,
    :process_run_id,
    :work_item_id,
    :expected_work_version
  ]

  # Availability is a capability and work-state read for the signed-in person:
  # it lists the actions whose capability the actor holds and, for work-bound
  # actions, each due available item of a running tenant run of this subject,
  # with the versions a page must echo back. Owner business eligibility is not
  # proved here; execution repeats every check under the subject lock.
  def available(scope, subject_ref) do
    with :ok <- human(scope),
         {:ok, ref} <- Definitions.subject(subject_ref),
         {:ok, subject} <- load(scope, ref, :read, :read) do
      actions = actions(ref)

      cond do
        actions == [] ->
          {:ok, %{subject_version: subject.version, actions: []}}

        is_nil(subject.version) ->
          {:error, :subject_version_unavailable}

        true ->
          permitted =
            Enum.filter(actions, &(capability(scope, ref, subject, &1.capability) == :ok))

          executors =
            permitted |> Enum.map(& &1.executor_key) |> Enum.reject(&is_nil/1) |> Enum.uniq()

          work = due_work(scope, subject_ref, executors)

          entries =
            Enum.flat_map(permitted, fn action ->
              if is_nil(action.executor_key) do
                [entry(action, nil)]
              else
                work
                |> Enum.filter(&(&1.executor_key == action.executor_key))
                |> Enum.map(&entry(action, &1))
              end
            end)

          {:ok, %{subject_version: subject.version, actions: entries}}
      end
    end
  end

  # Order under the subject lock: owner proof, capability, then the tenant/key
  # request row. A matching intent replays its saved result before any version
  # check, because the first execution legitimately changed the subject. Only
  # a new request compares the expected subject version, writes its row, runs
  # the owner handler and completes the bound work, all in one transaction.
  def execute(scope, subject_ref, request) do
    with :ok <- human(scope),
         {:ok, request} <- request(request),
         {:ok, ref} <- Definitions.subject(subject_ref),
         {:ok, action} <- action(ref, request.action_key),
         :ok <- binding(action, request) do
      Attribution.transact(scope, fn ->
        with {:ok, subject} <- load(scope, ref, :lock, :execute_action),
             :ok <- capability(scope, ref, subject, action.capability),
             {:ok, existing} <- lock_request(scope, request.idempotency_key) do
          case existing do
            nil -> perform(scope, ref, subject, action, request)
            row -> replay(scope, ref, row, request)
          end
        end
      end)
    end
  end

  defp perform(scope, ref, subject, action, request) do
    actor = Scope.actor(scope)

    with :ok <- version(subject, request.expected_subject_version),
         {:ok, hash} <- IntentDigest.digest(intent(ref.type, to_string(ref.id), actor, request)),
         {:ok, state, row} <- insert_request(scope, ref, action, request, actor, hash) do
      case state do
        :new -> run(scope, ref, subject, action, request, row)
        # A request for another subject of this tenant won the same key while
        # we held only our own subject lock; its committed intent decides.
        :existing -> replay(scope, ref, row, request)
      end
    end
  end

  defp run(scope, ref, subject, action, request, row) do
    actor = Scope.actor(scope)
    handler = fn -> handle(scope, subject, action, request) end

    completion =
      if action.executor_key do
        context = %{
          "action_key" => action.key,
          "request_id" => row.id,
          "actor_type" => "user",
          "actor_id" => actor.user_id,
          "source" => "human_action"
        }

        Coordination.complete_human(
          scope,
          ref,
          request.process_run_id,
          request.work_item_id,
          %{expected_version: request.expected_work_version, executor_key: action.executor_key},
          handler,
          context
        )
      else
        with {:ok, outcome} <- handler.(), do: {:ok, %{work_item: nil, outcome: outcome}}
      end

    with {:ok, %{work_item: item, outcome: outcome}} <- completion do
      result = %{
        "action_key" => action.key,
        "output" => outcome.output,
        "outcome" => outcome.outcome,
        "result_ref" => outcome.result_ref,
        "work_item_id" => item && item.id
      }

      time = now()

      row =
        row
        |> Ecto.Changeset.change(result: result, completed_at: time, updated_at: time)
        |> Repo.update!()

      {:ok, _} = audit(scope, ref, subject, row)
      {:ok, fact(row, false)}
    end
  end

  defp replay(scope, ref, row, request) do
    actor = Scope.actor(scope)

    with {:ok, stored} <- Definitions.subject(%{type: row.subject_type, id: row.subject_id}),
         true <- stored.type == ref.type and stored.id == ref.id,
         true <- row.action_key == request.action_key,
         {:ok, hash} <-
           IntentDigest.digest(intent(row.subject_type, row.subject_id, actor, request)),
         true <- same?(row.intent_hash, hash) do
      if is_nil(row.completed_at) or is_nil(row.result),
        do: {:error, :request_incomplete},
        else: {:ok, fact(row, true)}
    else
      _ -> {:error, :idempotency_conflict}
    end
  end

  defp handle(scope, subject, action, request) do
    facts =
      Map.take(request, [:action_key, :idempotency_key, :payload, :process_run_id, :work_item_id])

    case action.handler.handle(scope, subject, public_action(action), facts) do
      {:ok, outcome} when is_map(outcome) and not is_struct(outcome) ->
        outcome = Map.merge(%{output: %{}, outcome: "completed", result_ref: nil}, outcome)

        if Map.keys(outcome) -- [:output, :outcome, :result_ref] == [] and
             match?({:ok, _}, JSON.cast(outcome.output)) and text?(outcome.outcome) and
             (is_nil(outcome.result_ref) or text?(outcome.result_ref)),
           do: {:ok, outcome},
           else: {:error, :invalid_handler_outcome}

      {:error, _} = error ->
        error

      _other ->
        {:error, :invalid_handler_outcome}
    end
  end

  defp lock_request(scope, key) do
    {:ok,
     Repo.one(
       from(r in Tenancy.scope_query(RequestSchema, scope),
         where: r.idempotency_key == ^key,
         lock: "FOR UPDATE"
       )
     )}
  end

  # Insert-or-lock on the tenant/key constraint, as Coordination starts a run:
  # a competing insert on the same key blocks until it commits, after which
  # the committed row is read under our lock instead of raising.
  defp insert_request(scope, ref, action, request, actor, hash) do
    time = now()

    attrs = %{
      tenant_id: Scope.tenant_id(scope),
      idempotency_key: request.idempotency_key,
      intent_hash: hash,
      action_key: action.key,
      subject_type: ref.type,
      subject_id: to_string(ref.id),
      process_run_id: request.process_run_id,
      work_item_id: request.work_item_id,
      actor_type: "user",
      actor_id: actor.user_id,
      created_at: time,
      updated_at: time
    }

    {count, _} =
      Repo.insert_all(RequestSchema, [attrs],
        on_conflict: :nothing,
        conflict_target: [:tenant_id, :idempotency_key]
      )

    case lock_request(scope, request.idempotency_key) do
      {:ok, nil} -> {:error, :idempotency_conflict}
      {:ok, row} -> {:ok, if(count == 1, do: :new, else: :existing), row}
    end
  end

  defp intent(subject_type, subject_id, actor, request) do
    %{
      subject_type: subject_type,
      subject_id: subject_id,
      actor_type: Atom.to_string(actor.type),
      actor_id: actor.user_id,
      action_key: request.action_key,
      process_run_id: request.process_run_id,
      work_item_id: request.work_item_id,
      payload: request.payload
    }
  end

  defp version(%Subject{version: nil}, _expected), do: {:error, :subject_version_unavailable}

  defp version(%Subject{version: current}, expected),
    do: if(same?(current, expected), do: :ok, else: {:error, :stale_subject})

  defp same?(saved, given)
       when is_binary(saved) and is_binary(given) and byte_size(saved) == byte_size(given),
       do: :crypto.hash_equals(saved, given)

  defp same?(_saved, _given), do: false

  defp human(scope) do
    case Scope.actor(scope) do
      %{type: :user} -> :ok
      _ -> {:error, :human_actor_required}
    end
  end

  defp request(request) when is_map(request) and not is_struct(request) do
    request =
      Map.merge(
        %{payload: %{}, process_run_id: nil, work_item_id: nil, expected_work_version: nil},
        request
      )

    cond do
      Map.keys(request) -- @request_keys != [] ->
        {:error, :invalid_request}

      not (text?(request[:action_key]) and text?(request[:idempotency_key])) ->
        {:error, :invalid_request}

      not (is_binary(request[:expected_subject_version]) and
               request[:expected_subject_version] != "") ->
        {:error, :invalid_request}

      not Enum.all?(
        [:process_run_id, :work_item_id, :expected_work_version],
        &positive_or_nil?(request[&1])
      ) ->
        {:error, :invalid_request}

      not ((is_map(request.payload) or is_list(request.payload)) and
               match?({:ok, _}, JSON.cast(request.payload))) ->
        {:error, :invalid_request}

      not IntentDigest.reproducible?(request.payload) ->
        {:error, :unreproducible_intent}

      true ->
        {:ok, request}
    end
  end

  defp request(_request), do: {:error, :invalid_request}

  defp positive_or_nil?(value), do: is_nil(value) or (is_integer(value) and value > 0)

  defp binding(%{executor_key: nil}, request) do
    if is_nil(request.process_run_id) and is_nil(request.work_item_id) and
         is_nil(request.expected_work_version),
       do: :ok,
       else: {:error, :invalid_request}
  end

  defp binding(_action, request) do
    if request.process_run_id && request.work_item_id && request.expected_work_version,
      do: :ok,
      else: {:error, :work_binding_required}
  end

  defp action(ref, key) do
    case Map.get(Definitions.registry!().human_actions, {ref.type, key}) do
      %{owner: owner} = action when owner == ref.owner -> {:ok, action}
      _ -> {:error, :action_unavailable}
    end
  end

  defp actions(ref) do
    Definitions.registry!().human_actions
    |> Map.values()
    |> Enum.filter(&(&1.subject == ref.type and &1.owner == ref.owner))
    |> Enum.sort_by(& &1.key)
  end

  defp public_action(action),
    do: Map.take(action, [:key, :label, :subject, :capability, :executor_key])

  defp entry(action, item) do
    Map.merge(public_action(action), %{
      process_run_id: item && item.process_run_id,
      work_item_id: item && item.id,
      work_version: item && item.version
    })
  end

  defp due_work(_scope, _subject_ref, []), do: []

  defp due_work(scope, subject_ref, executors) do
    due_work(scope, subject: subject_ref, executor_keys: executors, limit: 500)
  end

  defp due_work(scope, opts) do
    case PendingWork.list(scope, opts) do
      {:ok, %{entries: entries, next_cursor: nil}} ->
        entries

      {:ok, %{entries: entries, next_cursor: cursor}} ->
        entries ++ due_work(scope, Keyword.put(opts, :after, cursor))

      {:error, _} ->
        []
    end
  end

  defp load(scope, ref, mode, operation) do
    with {:ok, %Subject{} = subject} <- ref.adapter.load(scope, ref.id, mode),
         true <- subject.id == ref.id and subject.tenant_id == Scope.tenant_id(scope),
         true <- is_nil(subject.version) or (is_binary(subject.version) and subject.version != ""),
         true <- match?({:ok, _}, JSON.cast(subject.facts)),
         :ok <- ref.adapter.authorize(scope, subject, operation) do
      {:ok, subject}
    else
      false -> {:error, :invalid_adapter_subject}
      {:error, _} = error -> error
      _ -> {:error, :invalid_adapter_subject}
    end
  end

  defp capability(scope, ref, subject, capability) do
    resource = Resource.new!(ref.type, ref.id, scope: scope, company_id: subject.company_id)

    if Authz.can(scope, capability, resource).allowed,
      do: :ok,
      else: {:error, :missing_capability}
  end

  defp audit(scope, ref, subject, row) do
    actor = Scope.actor(scope)

    Audit.record_action(scope, %{
      event: "workflow.human_action.completed",
      occurred_at: now(),
      actor_type: "user",
      actor_id: actor.user_id,
      company_id: subject.company_id,
      impersonator_id: actor.impersonator_id,
      system_principal: nil,
      payload: %{
        "subject_type" => ref.type,
        "subject_id" => to_string(ref.id),
        "action_key" => row.action_key,
        "request_id" => row.id,
        "process_run_id" => row.process_run_id,
        "work_item_id" => row.work_item_id
      }
    })
  end

  # Legacy results are read as saved; a row's own columns fill a field its
  # result JSON omits, and nothing is reinterpreted or executed.
  defp fact(row, replayed?) do
    result = if is_map(row.result), do: row.result, else: %{}

    %{
      request_id: row.id,
      action_key: Map.get(result, "action_key", row.action_key),
      outcome: Map.get(result, "outcome", "completed"),
      output: Map.get(result, "output", %{}),
      result_ref: Map.get(result, "result_ref"),
      process_run_id: row.process_run_id,
      work_item_id: Map.get(result, "work_item_id", row.work_item_id),
      replayed: replayed?
    }
  end

  defp text?(value),
    do:
      is_binary(value) and String.valid?(value) and String.trim(value) != "" and
        byte_size(value) <= 255

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
