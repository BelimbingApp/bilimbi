defmodule Bilimbi.Base.Workflow.Coordination do
  @moduledoc false
  import Ecto.Query
  alias Bilimbi.Base.{Audit, Repo, Tenancy}
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Tenancy.Scope

  alias Bilimbi.Base.Workflow.{
    Definitions,
    DependencySchema,
    EventSchema,
    JSON,
    ProcessVersionSchema,
    RunSchema,
    Subject,
    WorkSchema
  }

  @terminal_work ~w(completed failed waived blocked)
  @terminal_run ~w(completed failed blocked)

  def start(scope, definition_key, subject_ref, opts) do
    Scope.actor(scope)

    opts =
      Keyword.validate!(opts,
        version: nil,
        input: [],
        idempotency_key: nil,
        correlation_key: nil,
        priority: 0,
        available_at: nil
      )

    with {:ok, ref} <- Definitions.subject(subject_ref),
         {:ok, definition} <- definition(definition_key, opts[:version]),
         true <- definition.subject == ref.type and definition.owner == ref.owner,
         :ok <- start_options(opts) do
      write(scope, fn ->
        with {:ok, subject} <- load(scope, ref, :lock),
             :ok <- register_version(definition),
             attrs = start_attrs(scope, ref, definition, opts),
             true <- String.valid?(attrs.idempotency_key),
             :ok <- authorize(scope, ref, subject, definition, attrs, :start),
             {:ok, run, new?} <- insert_run(scope, attrs),
             :ok <- same_start(run, attrs, ref),
             :ok <- authorize_replay(scope, ref, subject, definition, run, new?),
             {:ok, run} <- initialize(scope, run, definition, new?) do
          {:ok, run_fact(run)}
        else
          false -> {:error, :invalid_start_options}
          {:error, _} = error -> error
        end
      end)
    else
      false -> {:error, :process_subject_mismatch}
      {:error, _} = error -> error
    end
  end

  def get(scope, run_id) do
    with_run(scope, run_id, :read, fn run, items, _dependencies, _definition ->
      {:ok, %{run: run_fact(run), work_items: Enum.map(items, &work_fact/1)}}
    end)
  end

  def reconcile(scope, run_id) do
    with_run(scope, run_id, :reconcile, fn run, items, dependencies, _definition ->
      {:ok, run} = settle(scope, run, items, dependencies, now())
      {:ok, run_fact(run)}
    end)
  end

  def complete(scope, run_id, item_ref, request) do
    with :ok <- completion_request(request) do
      with_run(scope, run_id, :complete, fn run, items, dependencies, _definition ->
        time = now()
        item = find_item(items, item_ref)

        with :ok <- available(run, item, request, time),
             {:ok, item} <-
               finish(item, "completed", request.outcome, request.output, nil, time, %{
                 result_ref: request.result_ref
               }),
             :ok <-
               append_event(scope, run, item, "work.completed", %{
                 "outcome" => item.outcome,
                 "output" => item.output,
                 "result_ref" => item.result_ref
               }),
             {:ok, run} <- settle(scope, run, replace(items, item), dependencies, time) do
          {:ok, %{run: run_fact(run), work_item: work_fact(item)}}
        end
      end)
    end
  end

  def supersede(scope, run_id, reason) when is_binary(reason) do
    if String.trim(reason) == "" do
      {:error, :reason_required}
    else
      with_run(scope, run_id, :supersede, fn run, items, _dependencies, _definition ->
        time = now()

        cond do
          run.status in @terminal_run ->
            {:ok, run_fact(run)}

          Enum.any?(items, &live_lease?(&1, time)) ->
            {:error, :live_lease}

          true ->
            items =
              Enum.map(items, fn item ->
                if item.status in @terminal_work do
                  item
                else
                  {:ok, item} = finish(item, "blocked", "blocked", nil, reason, time)

                  :ok =
                    append_event(scope, run, item, "work.blocked", %{
                      "outcome" => "blocked",
                      "reason" => reason,
                      "cause" => "process_superseded"
                    })

                  item
                end
              end)

            {:ok, run} = finish_run(scope, run, items, time)
            :ok = append_event(scope, run, nil, "process.superseded", %{"reason" => reason})
            {:ok, run_fact(run)}
        end
      end)
    end
  end

  def supersede(_scope, _run_id, _reason), do: {:error, :reason_required}

  def signal(scope, run_id, name, payload, key) do
    with true <- text?(name) and text?(key),
         {:ok, _} <- JSON.cast(payload),
         true <- String.valid?(idempotency_key("signal:#{run_id}:#{key}")) do
      with_run(scope, run_id, :signal, fn run, items, dependencies, _definition ->
        event_key = idempotency_key("signal:#{run.id}:#{key}")

        previous =
          Repo.one(
            from(e in Tenancy.scope_query(EventSchema, scope),
              where: e.process_run_id == ^run.id and e.idempotency_key == ^event_key
            )
          )

        cond do
          previous && previous.type == "signal.received" && is_map(previous.payload) &&
              Map.take(previous.payload, ["signal", "payload"]) === %{
                "signal" => name,
                "payload" => payload
              } ->
            {:ok, run_fact(run)}

          previous ->
            {:error, :idempotency_conflict}

          run.status != "running" ->
            {:error, :run_not_running}

          true ->
            time = now()

            items =
              Enum.map(items, fn item ->
                if item.required_signal == name and is_nil(item.signalled_at) and
                     item.status not in @terminal_work do
                  update!(item, %{signalled_at: time, signal_payload: payload, updated_at: time})
                else
                  item
                end
              end)

            :ok =
              append_event(
                scope,
                run,
                nil,
                "signal.received",
                %{"signal" => name, "payload" => payload},
                event_key
              )

            {:ok, run} = settle(scope, run, items, dependencies, time)
            {:ok, run_fact(run)}
        end
      end)
    else
      _ -> {:error, :invalid_signal}
    end
  end

  def events(scope, run_id, opts) do
    opts = Keyword.validate!(opts, limit: 50, after: 0)
    limit!(opts[:limit])

    unless is_integer(opts[:after]) and opts[:after] >= 0,
      do: raise(ArgumentError, "invalid event cursor")

    with_run(scope, run_id, :read, fn run, _items, _deps, _definition ->
      rows =
        Repo.all(
          from(e in Tenancy.scope_query(EventSchema, scope),
            where: e.process_run_id == ^run.id and e.sequence > ^opts[:after],
            order_by: [asc: e.sequence],
            limit: ^(opts[:limit] + 1)
          )
        )

      page = Enum.take(rows, opts[:limit])
      cursor = if length(rows) > opts[:limit], do: List.last(page).sequence
      {:ok, %{entries: Enum.map(page, &fact/1), next_cursor: cursor}}
    end)
  end

  # Lock order is subject -> run -> items. The first scoped run read resolves
  # identity only; all authority, graph and state are reread under the lock.
  # The owner adapter receives run facts to check its current round/attempt.
  defp with_run(scope, run_id, operation, fun) do
    Scope.actor(scope)

    write(scope, fn ->
      with {:ok, candidate} <- scoped_run(scope, run_id, false),
           {:ok, ref} <-
             Definitions.subject(%{type: candidate.subject_type, id: candidate.subject_id}),
           {:ok, subject} <- load(scope, ref, :lock),
           {:ok, run} <- scoped_run(scope, run_id, true),
           true <-
             run.subject_type == candidate.subject_type and run.subject_id == candidate.subject_id,
           {:ok, definition} <- supported(run, ref),
           :ok <- authorize(scope, ref, subject, definition, run, operation),
           {:ok, items, dependencies} <- graph(scope, run, definition) do
        fun.(run, items, dependencies, definition)
      else
        false -> {:error, :run_identity_changed}
        {:error, _} = error -> error
      end
    end)
  end

  defp scoped_run(scope, id, lock?) do
    query =
      from(r in Tenancy.scope_query(RunSchema, scope),
        where: r.id == ^id and r.scope_type == "tenant"
      )

    query = if lock?, do: from(r in query, lock: "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :run_not_found}
      run -> {:ok, run}
    end
  end

  defp load(scope, ref, mode) do
    with {:ok, %Subject{} = subject} <- ref.adapter.load(scope, ref.id, mode),
         true <- subject.id == ref.id and subject.tenant_id == Scope.tenant_id(scope),
         true <- match?({:ok, _}, JSON.cast(subject.facts)) do
      {:ok, subject}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_adapter_subject}
    end
  end

  defp authorize(scope, ref, subject, definition, run, operation) do
    with :ok <- ref.adapter.authorize(scope, subject, operation),
         :ok <- definition.adapter.authorize(scope, subject, run_fact(run), operation),
         do: :ok
  end

  defp definition(key, nil) do
    Definitions.registry!().processes
    |> Enum.filter(fn {{candidate, _version}, _} -> candidate == key end)
    |> Enum.max_by(fn {{_, version}, _} -> version end, fn -> nil end)
    |> case do
      nil -> {:error, :definition_unavailable}
      {_, definition} -> {:ok, definition}
    end
  end

  defp definition(key, version) do
    case Map.fetch(Definitions.registry!().processes, {key, version}) do
      :error -> {:error, :definition_unavailable}
      {:ok, definition} -> {:ok, definition}
    end
  end

  defp supported(run, ref) do
    with {:ok, definition} <- definition(run.definition_key, run.definition_version),
         true <- definition.subject == ref.type and definition.owner == ref.owner,
         true <- definition.fingerprint == run.definition_fingerprint,
         %{definition_fingerprint: fingerprint} <- Repo.one(version_query(definition)),
         true <- fingerprint == definition.fingerprint do
      {:ok, definition}
    else
      _ -> {:error, :definition_unavailable}
    end
  end

  defp version_query(definition) do
    from(v in ProcessVersionSchema,
      where: v.definition_key == ^definition.key and v.definition_version == ^definition.version,
      lock: "FOR SHARE"
    )
  end

  defp register_version(definition) do
    time = now()

    Repo.insert_all(
      ProcessVersionSchema,
      [
        %{
          definition_key: definition.key,
          definition_version: definition.version,
          definition_fingerprint: definition.fingerprint,
          created_at: time,
          updated_at: time
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:definition_key, :definition_version]
    )

    if Repo.one(version_query(definition)).definition_fingerprint == definition.fingerprint,
      do: :ok,
      else: {:error, :definition_version_changed}
  end

  defp start_attrs(scope, ref, definition, opts) do
    time = now()

    key =
      if opts[:idempotency_key],
        do:
          idempotency_key(
            "start:tenant:#{Scope.tenant_id(scope)}:#{definition.key}:#{opts[:idempotency_key]}"
          )

    %{
      id: nil,
      tenant_id: Scope.tenant_id(scope),
      scope_type: "tenant",
      definition_key: definition.key,
      definition_version: definition.version,
      definition_fingerprint: definition.fingerprint,
      subject_type: ref.type,
      subject_id: to_string(ref.id),
      input: opts[:input],
      idempotency_key: key,
      correlation_key: opts[:correlation_key],
      priority: opts[:priority],
      available_at: opts[:available_at] || time,
      status: "running",
      started_at: time,
      heartbeat_at: time,
      created_at: time,
      updated_at: time
    }
  end

  defp insert_run(scope, attrs) do
    {count, _} =
      Repo.insert_all(RunSchema, [Map.delete(attrs, :id)],
        on_conflict: :nothing,
        conflict_target: [:idempotency_key],
        returning: [:id]
      )

    query =
      from(r in Tenancy.scope_query(RunSchema, scope),
        where: r.idempotency_key == ^attrs.idempotency_key,
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      nil -> {:error, :idempotency_conflict}
      run -> {:ok, run, count == 1}
    end
  end

  defp authorize_replay(_scope, _ref, _subject, _definition, _run, true), do: :ok

  defp authorize_replay(scope, ref, subject, definition, run, false),
    do: authorize(scope, ref, subject, definition, run, :start)

  defp same_start(run, attrs, ref) do
    fields = [
      :definition_key,
      :definition_version,
      :definition_fingerprint,
      :correlation_key,
      :priority,
      :input
    ]

    with {:ok, stored} <- Definitions.subject(%{type: run.subject_type, id: run.subject_id}),
         true <-
           run.scope_type == "tenant" and stored.type == ref.type and stored.id == ref.id and
             Enum.all?(fields, &(Map.fetch!(run, &1) === Map.fetch!(attrs, &1))) do
      :ok
    else
      _ -> {:error, :idempotency_conflict}
    end
  end

  defp initialize(scope, run, definition, true) do
    :ok =
      append_event(scope, run, nil, "process.started", %{
        "definition_key" => run.definition_key,
        "definition_version" => run.definition_version,
        "subject_type" => run.subject_type,
        "subject_id" => run.subject_id,
        "correlation_key" => run.correlation_key,
        "priority" => run.priority,
        "available_at" => NaiveDateTime.to_iso8601(run.available_at)
      })

    items =
      Enum.map(definition.steps, fn step ->
        attrs =
          Map.take(step, [
            :label,
            :executor_key,
            :dependency_mode,
            :required_signal,
            :delay_seconds,
            :max_attempts,
            :priority,
            :input,
            :input_ref,
            :result_ref,
            :metadata
          ])
          |> Map.merge(%{
            tenant_id: run.tenant_id,
            process_run_id: run.id,
            step_key: step.key,
            status: "pending",
            version: 1,
            created_at: now(),
            updated_at: now()
          })

        item = %WorkSchema{} |> Ecto.Changeset.change(attrs) |> Repo.insert!()

        :ok =
          append_event(scope, run, item, "work.materialized", %{
            "step_key" => item.step_key,
            "executor_key" => item.executor_key
          })

        item
      end)

    by_key = Map.new(items, &{&1.step_key, &1})

    dependencies =
      for step <- definition.steps, dependency <- step.dependencies do
        attrs = %{
          tenant_id: run.tenant_id,
          work_item_id: by_key[step.key].id,
          depends_on_work_item_id: by_key[dependency.step_key].id,
          acceptable_outcomes: dependency.acceptable_outcomes,
          created_at: now(),
          updated_at: now()
        }

        %DependencySchema{} |> Ecto.Changeset.change(attrs) |> Repo.insert!()
      end

    settle(scope, run, items, dependencies, now())
  end

  defp initialize(scope, run, definition, false) do
    with {:ok, items, dependencies} <- graph(scope, run, definition),
         do: settle(scope, run, items, dependencies, now())
  end

  defp graph(scope, run, definition) do
    # This owner-local invariant proof checks run children, including any
    # contradictory tenant row a scoped read would hide. Read at most the
    # installed graph size plus one: surplus rows invalidate the graph without
    # making a bounded worklist load an unbounded or corrupt saved collection.
    # Nothing is returned before tenant/graph/definition agreement is proved.
    item_limit = length(definition.steps) + 1
    dependency_limit = Enum.sum(Enum.map(definition.steps, &length(&1.dependencies))) + 1

    items =
      Repo.all(
        from(w in WorkSchema,
          where: w.process_run_id == ^run.id,
          order_by: [asc: w.id],
          limit: ^item_limit,
          lock: "FOR UPDATE"
        )
      )

    ids = Enum.map(items, & &1.id)

    dependencies =
      Repo.all(
        from(d in DependencySchema,
          where: d.work_item_id in ^ids or d.depends_on_work_item_id in ^ids,
          order_by: [asc: d.id],
          limit: ^dependency_limit,
          lock: "FOR UPDATE"
        )
      )

    steps = Map.new(definition.steps, &{&1.key, &1})
    by_id = Map.new(items, &{&1.id, &1})
    tenant = Scope.tenant_id(scope)

    expected_dependencies =
      for step <- definition.steps,
          dependency <- step.dependencies,
          do: {step.key, dependency.step_key, Enum.sort(dependency.acceptable_outcomes)}

    actual_dependencies =
      Enum.map(dependencies, fn dep ->
        dependent = by_id[dep.work_item_id]
        prerequisite = by_id[dep.depends_on_work_item_id]

        if dependent && prerequisite && dep.tenant_id == tenant &&
             is_list(dep.acceptable_outcomes) do
          {dependent.step_key, prerequisite.step_key, Enum.sort(dep.acceptable_outcomes)}
        else
          :invalid
        end
      end)

    # Events belong to this same proved graph. EXISTS checks corruption without
    # loading the growing timeline; the run lock serializes our event writers.
    invalid_events? =
      Repo.exists?(
        from(e in EventSchema,
          where:
            e.process_run_id == ^run.id and
              (fragment("? IS DISTINCT FROM ?", e.tenant_id, ^tenant) or e.sequence < 1 or
                 (not is_nil(e.work_item_id) and e.work_item_id not in ^ids))
        )
      )

    valid? =
      not invalid_events? and run.status in ~w(running paused completed failed blocked) and
        length(items) == length(definition.steps) and
        Enum.all?(items, fn item ->
          step = steps[item.step_key]

          step && item.tenant_id == tenant && item.version >= 1 && item.attempts >= 0 &&
            item.status in ~w(pending available leased completed failed waived blocked) &&
            Enum.all?(
              [
                :label,
                :executor_key,
                :dependency_mode,
                :required_signal,
                :delay_seconds,
                :max_attempts,
                :priority,
                :input,
                :input_ref,
                :metadata
              ],
              &(Map.fetch!(item, &1) === Map.fetch!(step, &1))
            ) &&
            (item.status not in ["available", "leased"] or not is_nil(item.available_at)) &&
            (item.status != "leased" or
               (not is_nil(item.lease_expires_at) and not is_nil(item.lease_token)))
        end) and Enum.sort(actual_dependencies) == Enum.sort(expected_dependencies)

    if valid?, do: {:ok, items, dependencies}, else: {:error, :invalid_process_graph}
  end

  defp settle(_scope, %{status: status} = run, _items, _dependencies, _time)
       when status != "running",
       do: {:ok, run}

  defp settle(scope, run, items, dependencies, time) do
    items =
      Enum.map(items, fn item ->
        if item.status == "leased" and due?(item.lease_expires_at, time) do
          if item.attempts >= item.max_attempts do
            {:ok, item} =
              finish(
                item,
                "failed",
                "failed",
                nil,
                "Worker lease expired after the final attempt.",
                time
              )

            :ok =
              append_event(scope, run, item, "work.lease_expired_failed", %{
                "attempt" => item.attempts
              })

            item
          else
            item =
              update!(item, %{
                status: "pending",
                available_at: time,
                lease_owner: nil,
                lease_token: nil,
                lease_expires_at: nil,
                heartbeat_at: nil,
                version: item.version + 1,
                last_error: "Worker lease expired; work returned to the queue.",
                updated_at: time
              })

            :ok =
              append_event(scope, run, item, "work.lease_expired_requeued", %{
                "attempt" => item.attempts
              })

            item
          end
        else
          item
        end
      end)

    items = release_pending(scope, run, items, dependencies, time)
    run = update!(run, %{heartbeat_at: time, updated_at: time})
    finish_run(scope, run, items, time)
  end

  defp release_pending(scope, run, items, dependencies, time) do
    {items, changed?} =
      Enum.map_reduce(items, false, fn item, changed? ->
        if item.status == "pending" do
          case dependency_state(item, items, dependencies) do
            :impossible ->
              reason = "No acceptable dependency outcome remains."
              {:ok, item} = finish(item, "blocked", "blocked", nil, reason, time)
              :ok = append_event(scope, run, item, "work.blocked", %{"reason" => reason})
              {item, true}

            :satisfied ->
              if is_nil(item.required_signal) or not is_nil(item.signalled_at) do
                item = start_timer(scope, run, item, time)

                if due?(item.available_at, time) do
                  item = update!(item, %{status: "available", updated_at: time})
                  :ok = append_event(scope, run, item, "work.available", nil)
                  {item, true}
                else
                  {item, changed?}
                end
              else
                {item, changed?}
              end

            :waiting ->
              {item, changed?}
          end
        else
          {item, changed?}
        end
      end)

    if changed?, do: release_pending(scope, run, items, dependencies, time), else: items
  end

  defp dependency_state(item, items, dependencies) do
    by_id = Map.new(items, &{&1.id, &1})

    states =
      for dependency <- dependencies, dependency.work_item_id == item.id do
        prerequisite = Map.fetch!(by_id, dependency.depends_on_work_item_id)

        cond do
          prerequisite.status not in @terminal_work -> :waiting
          prerequisite.outcome in dependency.acceptable_outcomes -> :accepted
          true -> :rejected
        end
      end

    cond do
      states == [] -> :satisfied
      item.dependency_mode == "any" and :accepted in states -> :satisfied
      item.dependency_mode == "any" and :waiting in states -> :waiting
      item.dependency_mode == "any" -> :impossible
      :rejected in states -> :impossible
      :waiting in states -> :waiting
      true -> :satisfied
    end
  end

  defp start_timer(scope, run, %{available_at: nil} = item, time) do
    base =
      if NaiveDateTime.compare(run.available_at, time) == :gt, do: run.available_at, else: time

    item =
      update!(item, %{available_at: NaiveDateTime.add(base, item.delay_seconds), updated_at: time})

    :ok =
      append_event(scope, run, item, "work.timer_started", %{
        "available_at" => NaiveDateTime.to_iso8601(item.available_at)
      })

    item
  end

  defp start_timer(_scope, _run, item, _time), do: item

  defp finish_run(scope, run, items, time) do
    if run.status not in @terminal_run and Enum.all?(items, &(&1.status in @terminal_work)) do
      status =
        cond do
          Enum.any?(items, &(&1.status == "failed")) -> "failed"
          Enum.any?(items, &(&1.status == "blocked")) -> "blocked"
          true -> "completed"
        end

      output =
        Map.new(
          items,
          &{&1.step_key, %{"status" => &1.status, "outcome" => &1.outcome, "output" => &1.output}}
        )

      error = Enum.find_value(items, & &1.last_error)

      run =
        update!(run, %{
          status: status,
          output: output,
          last_error: error,
          completed_at: time,
          heartbeat_at: time,
          updated_at: time
        })

      :ok = append_event(scope, run, nil, "process." <> status, %{"output" => output})
      {:ok, run}
    else
      {:ok, run}
    end
  end

  defp finish(item, status, outcome, output, error, time, extra \\ %{}) do
    attrs =
      %{
        version: item.version + 1,
        status: status,
        outcome: outcome,
        output: output,
        last_error: error,
        lease_owner: nil,
        lease_token: nil,
        lease_expires_at: nil,
        heartbeat_at: nil,
        completed_at: time,
        updated_at: time
      }
      |> Map.merge(extra)

    {:ok, update!(item, attrs)}
  end

  # The caller holds the run lock. Sequence allocation and all state writes
  # commit together; three competing completions cannot allocate one sequence.
  defp append_event(scope, run, item, type, payload, key \\ nil) do
    sequence =
      Repo.one(
        from(e in EventSchema,
          where: e.process_run_id == ^run.id,
          select: max(e.sequence)
        )
      ) || 0

    attrs = %{
      tenant_id: run.tenant_id,
      process_run_id: run.id,
      work_item_id: item && item.id,
      sequence: sequence + 1,
      type: type,
      payload: payload,
      idempotency_key: key,
      occurred_at: now(),
      created_at: now()
    }

    event = %EventSchema{} |> Ecto.Changeset.change(attrs) |> Repo.insert!()
    actor = Scope.actor(scope)

    {:ok, _} =
      Audit.record_action(scope, %{
        event: "workflow." <> type,
        occurred_at: now(),
        actor_type: Atom.to_string(actor.type),
        actor_id: actor.user_id || 0,
        company_id: actor.company_id,
        impersonator_id: actor.impersonator_id,
        system_principal: actor.system_principal,
        payload: %{
          "process_run_id" => run.id,
          "work_item_id" => item && item.id,
          "event_id" => event.id
        }
      })

    :ok
  end

  defp available(_run, nil, _request, _time), do: {:error, :work_not_found}

  defp available(run, item, request, time) do
    cond do
      run.status != "running" ->
        {:error, :run_not_running}

      item.status != "available" ->
        {:error, :work_not_available}

      not is_nil(run.last_error) ->
        {:error, :run_unavailable}

      not due?(run.available_at, time) or not due?(item.available_at, time) ->
        {:error, :work_not_due}

      item.executor_key != request.executor_key ->
        {:error, :executor_mismatch}

      item.version != request.expected_version ->
        {:error, :stale_work}

      true ->
        :ok
    end
  end

  defp completion_request(request) when is_map(request) and not is_struct(request) do
    allowed = [:expected_version, :executor_key, :outcome, :output, :result_ref]

    if Map.keys(request) -- allowed == [] and
         is_integer(request[:expected_version]) and request[:expected_version] >= 1 and
         text?(request[:executor_key]) and text?(request[:outcome]) and
         Map.has_key?(request, :output) and Map.has_key?(request, :result_ref) and
         (is_nil(request[:result_ref]) or text?(request[:result_ref])) and
         match?({:ok, _}, JSON.cast(request[:output])),
       do: :ok,
       else: {:error, :invalid_completion}
  end

  defp completion_request(_request), do: {:error, :invalid_completion}

  defp start_options(opts) do
    valid? =
      text?(opts[:idempotency_key]) and
        (is_nil(opts[:correlation_key]) or text?(opts[:correlation_key])) and
        is_integer(opts[:priority]) and opts[:priority] in -2_147_483_648..2_147_483_647 and
        (is_nil(opts[:available_at]) or
           match?(%NaiveDateTime{microsecond: {0, 0}}, opts[:available_at])) and
        match?({:ok, _}, JSON.cast(opts[:input]))

    if valid?, do: :ok, else: {:error, :invalid_start_options}
  end

  defp find_item(items, %{step_key: key}), do: Enum.find(items, &(&1.step_key == key))
  defp find_item(items, id) when is_integer(id), do: Enum.find(items, &(&1.id == id))
  defp find_item(_items, _ref), do: nil

  defp replace(items, updated),
    do: Enum.map(items, &if(&1.id == updated.id, do: updated, else: &1))

  defp live_lease?(item, time),
    do:
      item.status == "leased" and not is_nil(item.lease_expires_at) and
        not due?(item.lease_expires_at, time)

  defp due?(nil, _time), do: false
  defp due?(at, time), do: NaiveDateTime.compare(at, time) != :gt
  defp update!(row, attrs), do: row |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp fact(row), do: row |> Map.from_struct() |> Map.delete(:__meta__)
  defp work_fact(row), do: row |> fact() |> Map.drop([:lease_token, :lease_owner])
  defp run_fact(%RunSchema{} = row), do: fact(row)
  defp run_fact(attrs) when is_map(attrs), do: attrs
  # Source keys use the literal namespace through 240 bytes; longer keys keep
  # the first 170 bytes plus the SHA-256 of the whole namespace. This keeps a
  # repeated start/signal attached to its adopted run rather than duplicating it.
  defp idempotency_key(raw) when byte_size(raw) <= 240, do: raw

  defp idempotency_key(raw),
    do:
      binary_part(raw, 0, 170) <>
        ":" <> (:crypto.hash(:sha256, raw) |> Base.encode16(case: :lower))

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  defp text?(value),
    do:
      is_binary(value) and String.valid?(value) and String.trim(value) != "" and
        byte_size(value) <= 255

  defp limit!(value),
    do:
      unless(is_integer(value) and value in 1..500,
        do: raise(ArgumentError, "limit must be 1..500")
      )

  defp write(scope, fun) do
    actor = Scope.actor(scope)

    if actor.type == :user or is_binary(actor.system_principal) do
      previous = AuditContext.get()

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
        Repo.transact(fun)
      after
        AuditContext.put(previous)
      end
    else
      {:error, :no_authenticated_actor}
    end
  end
end
