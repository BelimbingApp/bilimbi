defmodule Bilimbi.Base.Workflow.Definitions do
  @moduledoc false
  import Ecto.Query
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Workflow.{EdgeSchema, FlowSchema, KanbanSchema, StatusSchema}

  def registry!, do: ContributionRegistry.consumer!(:workflow)

  def subject(ref) do
    with %{type: type, id: id} <- ref,
         {:ok, id} <- numeric_id(id),
         {:ok, key} <- Map.fetch(registry!().aliases, {:subjects, type}),
         {:ok, adapter} <- Map.fetch(registry!().subjects, key) do
      flow =
        Enum.find_value(registry!().flows, fn {code, flow} -> if flow.subject == key, do: code end)

      {:ok, %{type: key, id: id, adapter: adapter.adapter, owner: adapter.owner, flow: flow}}
    else
      _ -> {:error, :unknown_subject}
    end
  end

  def hook(_kind, nil, _owner), do: {:ok, nil}

  def hook(kind, value, owner) do
    with {:ok, key} <- Map.fetch(registry!().aliases, {kind, value}),
         %{owner: ^owner, adapter: adapter} <- Map.get(Map.fetch!(registry!(), kind), key) do
      {:ok, %{key: key, adapter: adapter}}
    else
      _ -> {:error, :adapter_unavailable}
    end
  end

  def flow(%{flow: nil}, _mode), do: {:error, :flow_unavailable}

  def flow(ref, mode) do
    query = from(f in FlowSchema, where: f.code == ^ref.flow)
    # Inactive legacy flows still contain history the proven owner may adopt.
    query = if mode == :adopt, do: query, else: from(f in query, where: f.is_active)
    query = if mode in [:lock, :adopt], do: from(f in query, lock: "FOR SHARE"), else: query

    case Repo.one(query) do
      nil ->
        {:error, :flow_unavailable}

      flow ->
        with {:ok, key} <- Map.fetch(registry!().aliases, {:subjects, flow.model_class}),
             true <- key == ref.type do
          {:ok, flow}
        else
          _ -> {:error, :flow_unavailable}
        end
    end
  end

  def status?(flow, status, mode) do
    query = from(s in StatusSchema, where: s.flow == ^flow and s.code == ^status and s.is_active)
    query = if mode == :lock, do: from(s in query, lock: "FOR SHARE"), else: query
    not is_nil(Repo.one(query))
  end

  def edges(flow, status, mode) do
    query =
      from(e in EdgeSchema,
        where: e.flow == ^flow and e.from_code == ^status and e.is_active,
        order_by: [asc: e.position, asc: e.id]
      )

    query = if mode == :lock, do: from(e in query, lock: "FOR SHARE"), else: query
    Repo.all(query)
  end

  # Explicit insert-only initialization. Adoption never invokes this and boot
  # never writes definitions. Existing rows, inactive flags and PHP identities
  # win; a contribution cannot silently replace operator configuration.
  def seed do
    Repo.transact(fn ->
      for {_code, flow} <- registry!().flows do
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        insert_missing(
          FlowSchema,
          Map.take(flow, [:code, :label, :description, :settings, :is_active])
          |> Map.merge(%{module: flow.owner, model_class: flow.subject}),
          [:code],
          now
        )

        for status <- flow.statuses,
            do:
              insert_missing(StatusSchema, Map.put(status, :flow, flow.code), [:flow, :code], now)

        for column <- flow.kanban,
            do:
              insert_missing(KanbanSchema, Map.put(column, :flow, flow.code), [:flow, :code], now)

        for edge <- flow.transitions do
          attrs =
            Map.drop(edge, [:from, :to, :guard, :action])
            |> Map.merge(%{
              flow: flow.code,
              from_code: edge.from,
              to_code: edge.to,
              guard_class: edge.guard,
              action_class: edge.action
            })

          insert_missing(EdgeSchema, attrs, [:flow, :from_code, :to_code], now)
        end
      end

      {:ok, :seeded}
    end)
  end

  defp insert_missing(schema, attrs, conflict_target, now) do
    Repo.insert_all(schema, [Map.merge(attrs, %{created_at: now, updated_at: now})],
      on_conflict: :nothing,
      conflict_target: conflict_target
    )
  end

  def numeric_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
    do: {:ok, id}

  def numeric_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 ->
        if Integer.to_string(number) == id, do: numeric_id(number), else: :error

      _ ->
        :error
    end
  end

  def numeric_id(_id), do: :error
end
