defmodule Bilimbi.Base.Menu.ContributionValidator do
  @moduledoc """
  Validates every installed module's menu contribution into one ordered list.

  Follows Belimbing's `MenuRegistry`: the complete discovered set is indexed
  first and parents are validated only afterwards, so contribution order never
  decides whether an item resolves. An item whose parent is missing is dropped
  with a warning rather than raising — one module shipping a dangling parent
  must not take down navigation for every other module.

  Duplicate ids and circular parents *do* raise. Those are contributor defects
  with no safe interpretation, and silently keeping one of two same-id items
  would make navigation depend on load order.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  require Logger

  alias Bilimbi.Base.Menu.Item

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: [Item.t()]
  def validate_contributions!(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(&entry_items!/1)
    |> reject_duplicate_ids!()
    |> drop_unresolvable_parents()
    |> reject_cycles!()
    |> sort()
  end

  defp entry_items!(%{descriptor: descriptor, payload: payload}) do
    unless is_list(payload) do
      raise ArgumentError, "menu contribution from #{descriptor.id} must be a list"
    end

    Enum.map(payload, fn attrs ->
      unless is_map(attrs) do
        raise ArgumentError, "menu contribution from #{descriptor.id} must contain maps"
      end

      {Item.new!(attrs), descriptor.id}
    end)
  end

  defp reject_duplicate_ids!(pairs) do
    duplicates =
      pairs
      |> Enum.group_by(fn {item, _owner} -> item.id end)
      |> Enum.filter(fn {_id, group} -> length(group) > 1 end)

    if duplicates != [] do
      detail =
        Enum.map_join(duplicates, "; ", fn {id, group} ->
          owners = group |> Enum.map_join(", ", fn {_item, owner} -> owner end)
          "#{id} contributed by #{owners}"
        end)

      raise ArgumentError, "duplicate menu item ids: #{detail}"
    end

    pairs
  end

  # Belimbing indexes the whole set before validating parents, so an item may
  # legitimately name a parent contributed by a different module.
  defp drop_unresolvable_parents(pairs) do
    ids = MapSet.new(pairs, fn {item, _owner} -> item.id end)

    Enum.filter(pairs, fn {item, owner} ->
      if is_nil(item.parent) or MapSet.member?(ids, item.parent) do
        true
      else
        Logger.warning(
          "menu item #{item.id} from #{owner} names missing parent #{item.parent}; dropping it"
        )

        false
      end
    end)
  end

  defp reject_cycles!(pairs) do
    by_id = Map.new(pairs, fn {item, _owner} -> {item.id, item} end)

    Enum.each(by_id, fn {id, _item} -> walk!(id, by_id, MapSet.new()) end)

    Enum.map(pairs, fn {item, _owner} -> item end)
  end

  defp walk!(nil, _by_id, _seen), do: :ok

  defp walk!(id, by_id, seen) do
    if MapSet.member?(seen, id) do
      raise ArgumentError, "circular menu parent reference at #{id}"
    end

    case Map.get(by_id, id) do
      nil -> :ok
      item -> walk!(item.parent, by_id, MapSet.put(seen, id))
    end
  end

  # Deterministic across runs: contribution order must never change the menu.
  defp sort(items), do: Enum.sort_by(items, &{&1.order, &1.id})
end
