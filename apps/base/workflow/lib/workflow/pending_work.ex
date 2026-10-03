defmodule Bilimbi.Base.Workflow.PendingWork do
  @moduledoc false
  import Ecto.Query
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.{Coordination, Definitions, RunSchema, WorkSchema}

  # This is a bounded Workflow worklist, not an owner workbench count. Advance
  # by the last scanned candidate even if owner policy hides some candidates.
  # Owner current-round/company filters belong to its adapter; no private owner
  # relation crosses this boundary and execution repeats all checks.
  def list(scope, opts) do
    Scope.actor(scope)

    opts =
      Keyword.validate!(opts,
        limit: 50,
        after: nil,
        subject: nil,
        run_id: nil,
        definition_key: nil,
        executor_keys: nil
      )

    unless is_integer(opts[:limit]) and opts[:limit] in 1..500,
      do: raise(ArgumentError, "pending work limit must be 1..500")

    time = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    query =
      from(w in Tenancy.scope_query(WorkSchema, scope),
        join: r in subquery(Tenancy.scope_query(RunSchema, scope)),
        on: r.id == w.process_run_id,
        where:
          r.scope_type == "tenant" and r.status == "running" and is_nil(r.last_error) and
            r.available_at <= ^time and w.status == "available" and w.available_at <= ^time,
        order_by: [desc: w.priority, asc: w.available_at, asc: w.id],
        limit: ^(opts[:limit] + 1),
        select: %{id: w.id, run_id: r.id, priority: w.priority, available_at: w.available_at}
      )

    with {:ok, query} <- filters(query, opts) do
      rows = Repo.all(cursor(query, opts[:after]))
      page = Enum.take(rows, opts[:limit])

      run_facts =
        page
        |> Enum.map(& &1.run_id)
        |> Enum.uniq()
        |> Map.new(fn id -> {id, Coordination.get(scope, id)} end)

      entries =
        Enum.flat_map(page, fn candidate ->
          with {:ok, %{run: run, work_items: items}} <- Map.fetch!(run_facts, candidate.run_id),
               true <-
                 run.status == "running" and is_nil(run.last_error) and
                   NaiveDateTime.compare(run.available_at, time) != :gt,
               item when not is_nil(item) <- Enum.find(items, &(&1.id == candidate.id)),
               true <-
                 item.status == "available" and not is_nil(item.available_at) and
                   NaiveDateTime.compare(item.available_at, time) != :gt do
            [
              Map.merge(item, %{
                subject: %{type: run.subject_type, id: run.subject_id},
                definition_key: run.definition_key,
                definition_version: run.definition_version
              })
            ]
          else
            _ -> []
          end
        end)

      next =
        if length(rows) > opts[:limit] do
          last = List.last(page)
          {last.priority, last.available_at, last.id}
        end

      {:ok, %{entries: entries, next_cursor: next}}
    end
  end

  defp filters(query, opts) do
    query =
      if opts[:run_id], do: from([w, r] in query, where: r.id == ^opts[:run_id]), else: query

    query =
      if opts[:definition_key],
        do: from([w, r] in query, where: r.definition_key == ^opts[:definition_key]),
        else: query

    query =
      if opts[:executor_keys],
        do: from([w, _r] in query, where: w.executor_key in ^opts[:executor_keys]),
        else: query

    if opts[:subject] do
      with {:ok, ref} <- Definitions.subject(opts[:subject]) do
        aliases = Definitions.registry!().subjects[ref.type].aliases
        types = [ref.type | aliases]

        {:ok,
         from([_w, r] in query,
           where: r.subject_type in ^types and r.subject_id == ^to_string(ref.id)
         )}
      end
    else
      {:ok, query}
    end
  end

  defp cursor(query, nil), do: query

  defp cursor(query, {priority, %NaiveDateTime{} = time, id})
       when is_integer(priority) and is_integer(id) and id > 0,
       do:
         from([w, _r] in query,
           where:
             w.priority < ^priority or
               (w.priority == ^priority and w.available_at > ^time) or
               (w.priority == ^priority and w.available_at == ^time and w.id > ^id)
         )

  defp cursor(_query, _cursor), do: raise(ArgumentError, "invalid pending work cursor")
end
