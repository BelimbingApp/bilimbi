defmodule Bilimbi.Base.Dashboard.ContributionValidator do
  @moduledoc """
  Validates every installed module's dashboard widget contribution into one
  ordered list.

  Rejects duplicate ids (contributor defects), but tolerates missing capability
  modules (the widget is skipped rather than crashing the dashboard).
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Dashboard.Widget

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: [Widget.t()]
  def validate_contributions!(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(&entry_widgets!/1)
    |> reject_duplicate_ids!()
    |> sort()
  end

  defp entry_widgets!(%{descriptor: descriptor, payload: payload}) do
    unless is_list(payload) do
      raise ArgumentError,
            "dashboard contribution from #{descriptor.id} must be a list of widget maps"
    end

    Enum.map(payload, fn attrs ->
      unless is_map(attrs) do
        raise ArgumentError,
              "dashboard contribution from #{descriptor.id} must contain widget maps"
      end

      {Widget.new!(attrs), descriptor.id}
    end)
  end

  defp reject_duplicate_ids!(pairs) do
    duplicates =
      pairs
      |> Enum.group_by(fn {widget, _owner} -> widget.id end)
      |> Enum.filter(fn {_id, group} -> length(group) > 1 end)

    if duplicates != [] do
      detail =
        Enum.map_join(duplicates, "; ", fn {id, group} ->
          owners = group |> Enum.map_join(", ", fn {_widget, owner} -> owner end)
          "#{id} contributed by #{owners}"
        end)

      raise ArgumentError, "duplicate widget ids: #{detail}"
    end

    pairs
  end

  # Deterministic across runs: contribution order must never change the dashboard.
  defp sort(pairs) do
    pairs
    |> Enum.sort_by(fn {widget, _owner} -> {widget.order, widget.id} end)
    |> Enum.map(fn {widget, _owner} -> widget end)
  end
end
