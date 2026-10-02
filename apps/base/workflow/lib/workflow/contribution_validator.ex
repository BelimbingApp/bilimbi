defmodule Bilimbi.Base.Workflow.ContributionValidator do
  @moduledoc """
  Validates owner-proven plain-data status definitions and adapter keys.

  Only descriptor-owned compiled adapters execute. Legacy aliases are exact
  data lookups, never module names or prefix dispatch. One owner controls each
  subject and flow; duplicate keys or aliases fail regardless of install order.
  """
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Workflow.{ActionAdapter, GuardAdapter, JSON, SubjectAdapter}

  @impl true
  def validate_contributions!(entries) do
    registry = %{subjects: %{}, guards: %{}, actions: %{}, flows: %{}, aliases: %{}}
    registry = Enum.reduce(entries, registry, &collect!/2)
    Enum.each(registry.flows, fn {_key, flow} -> validate_flow_links!(registry, flow) end)
    registry
  end

  defp collect!(%{descriptor: descriptor, payload: payload}, registry) do
    unless "base/workflow" in Map.get(descriptor, :dependencies, []) or
             descriptor.id == "base/workflow",
           do: invalid!("#{descriptor.id} must declare base/workflow")

    keys!(payload, [:subjects, :guards, :actions, :flows])

    registry =
      Enum.reduce(
        [subjects: SubjectAdapter, guards: GuardAdapter, actions: ActionAdapter],
        registry,
        fn {kind, behaviour}, acc ->
          Enum.reduce(list!(payload, kind), acc, fn entry, acc ->
            adapter!(entry, descriptor, behaviour)
            key = entry.key

            value =
              Map.merge(entry, %{owner: descriptor.id, aliases: Map.get(entry, :aliases, [])})

            acc = unique_put!(acc, kind, key, value)

            alias_put!(acc, kind, key, key)
            |> then(fn acc -> Enum.reduce(value.aliases, acc, &alias_put!(&2, kind, &1, key)) end)
          end)
        end
      )

    Enum.reduce(list!(payload, :flows), registry, fn flow, acc ->
      flow = flow!(flow) |> Map.put(:owner, descriptor.id)
      unique_put!(acc, :flows, flow.code, flow)
    end)
  end

  defp adapter!(entry, descriptor, behaviour) do
    keys!(entry, [:key, :adapter, :aliases])
    key!(Map.get(entry, :key))
    aliases = Map.get(entry, :aliases, [])

    unless is_list(aliases) and
             Enum.all?(aliases, &(is_binary(&1) and &1 != "" and byte_size(&1) <= 255)),
           do: invalid!("aliases must be exact nonempty strings")

    adapter = Map.get(entry, :adapter)

    unless is_atom(adapter) and adapter not in [nil, true, false] and Code.ensure_loaded?(adapter),
      do: invalid!("adapter is not a compiled module")

    unless adapter in (Application.spec(descriptor.otp_app, :modules) || []),
      do: invalid!("#{inspect(adapter)} does not belong to #{descriptor.id}")

    behaviours =
      adapter.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

    callbacks = behaviour.behaviour_info(:callbacks)

    unless behaviour in behaviours and
             Enum.all?(callbacks, fn {name, arity} -> function_exported?(adapter, name, arity) end),
           do: invalid!("#{inspect(adapter)} must implement #{inspect(behaviour)}")
  end

  defp flow!(flow) do
    keys!(flow, [
      :code,
      :label,
      :subject,
      :description,
      :settings,
      :is_active,
      :statuses,
      :transitions,
      :kanban
    ])

    key!(Map.get(flow, :code))
    key!(Map.get(flow, :subject))
    string!(Map.get(flow, :label))
    statuses = Enum.map(list!(flow, :statuses), &status!/1)
    unless statuses != [], do: invalid!("a flow needs statuses")
    distinct!(statuses, & &1.code)
    transitions = Enum.map(list!(flow, :transitions), &edge!/1)
    distinct!(transitions, &{&1.from, &1.to})
    kanban = Enum.map(list!(flow, :kanban), &kanban!/1)
    distinct!(kanban, & &1.code)
    validate_optional!(flow, [:settings])

    Map.merge(%{description: nil, settings: nil, is_active: true}, flow)
    |> Map.merge(%{statuses: statuses, transitions: transitions, kanban: kanban})
  end

  defp status!(status) do
    keys!(status, [
      :code,
      :label,
      :position,
      :is_active,
      :pic,
      :notifications,
      :comment_tags,
      :prompt,
      :kanban_code
    ])

    key!(Map.get(status, :code))
    string!(Map.get(status, :label))
    validate_optional!(status, [:pic, :notifications, :comment_tags])
    Map.merge(%{position: 0, is_active: true}, status)
  end

  defp kanban!(column) do
    keys!(column, [:code, :label, :position, :is_active, :wip_limit, :settings, :description])
    key!(Map.get(column, :code))
    string!(Map.get(column, :label))
    validate_optional!(column, [:settings])
    limit = Map.get(column, :wip_limit)
    unless is_nil(limit) or (is_integer(limit) and limit >= 0), do: invalid!("invalid wip_limit")
    Map.merge(%{position: 0, is_active: true}, column)
  end

  defp edge!(edge) do
    keys!(edge, [
      :from,
      :to,
      :label,
      :capability,
      :guard,
      :action,
      :sla_seconds,
      :metadata,
      :position,
      :is_active
    ])

    key!(Map.get(edge, :from))
    key!(Map.get(edge, :to))

    for key <- [:capability, :guard, :action],
        value = Map.get(edge, key),
        not is_nil(value),
        do: key!(value)

    validate_optional!(edge, [:metadata])
    seconds = Map.get(edge, :sla_seconds)

    unless is_nil(seconds) or (is_integer(seconds) and seconds >= 0),
      do: invalid!("invalid sla_seconds")

    Map.merge(%{position: 0, is_active: true, capability: nil, guard: nil, action: nil}, edge)
  end

  defp validate_optional!(entry, json_fields) do
    for field <- json_fields do
      unless match?({:ok, _}, JSON.cast(Map.get(entry, field))),
        do: invalid!("invalid JSON for #{field}")
    end

    unless is_boolean(Map.get(entry, :is_active, true)), do: invalid!("invalid is_active")
    unless is_integer(Map.get(entry, :position, 0)), do: invalid!("invalid position")

    for field <- [:label, :prompt, :description, :kanban_code],
        value = Map.get(entry, field),
        not is_nil(value),
        do: string!(value)
  end

  defp validate_flow_links!(registry, flow) do
    owned!(registry.subjects, flow.subject, flow.owner)
    codes = Enum.map(flow.statuses, & &1.code)

    for edge <- flow.transitions do
      unless edge.from in codes and edge.to in codes,
        do: invalid!("edge names unknown status in #{flow.code}")

      for {kind, value} <- [guards: edge.guard, actions: edge.action],
          not is_nil(value),
          do: owned!(Map.fetch!(registry, kind), value, flow.owner)
    end

    columns = Enum.map(flow.kanban, & &1.code)

    for status <- flow.statuses, column = Map.get(status, :kanban_code), not is_nil(column) do
      unless column in columns, do: invalid!("unknown kanban column #{column}")
    end

    # One binding per stable subject/id: a subject has exactly one status flow.
    owners =
      Enum.filter(registry.flows, fn {_code, candidate} -> candidate.subject == flow.subject end)

    unless length(owners) == 1, do: invalid!("subject #{flow.subject} has multiple flows")
  end

  defp owned!(entries, key, owner) do
    case Map.get(entries, key) do
      %{owner: ^owner} = entry -> entry
      _ -> invalid!("#{key} is missing or belongs to another owner")
    end
  end

  defp unique_put!(registry, kind, key, value) do
    if Map.has_key?(Map.fetch!(registry, kind), key), do: invalid!("duplicate #{kind} key #{key}")
    put_in(registry, [kind, key], value)
  end

  defp alias_put!(registry, kind, alias_value, key) do
    identity = {kind, alias_value}

    if Map.has_key?(registry.aliases, identity),
      do: invalid!("duplicate #{kind} alias #{alias_value}")

    put_in(registry, [:aliases, identity], key)
  end

  defp keys!(map, allowed) when is_map(map) and not is_struct(map) do
    unless Map.keys(map) -- allowed == [], do: invalid!("unknown fields")
  end

  defp keys!(_map, _allowed), do: invalid!("expected a plain map")

  defp list!(map, key) do
    value = Map.get(map, key, [])
    unless is_list(value), do: invalid!("#{key} must be a list")
    value
  end

  defp distinct!(entries, key_fun) do
    keys = Enum.map(entries, key_fun)
    unless length(keys) == length(Enum.uniq(keys)), do: invalid!("duplicate definition entries")
  end

  defp string!(value) do
    unless is_binary(value) and value != "", do: invalid!("expected a nonempty string")
  end

  defp key!(value) do
    unless is_binary(value) and byte_size(value) <= 255 and
             Regex.match?(~r/\A[a-z][a-z0-9_-]*(?:\.[a-z][a-z0-9_-]*)*\z/, value),
           do: invalid!("expected a stable public key, got #{inspect(value)}")
  end

  defp invalid!(message), do: raise(ArgumentError, "invalid workflow contribution: #{message}")
end
