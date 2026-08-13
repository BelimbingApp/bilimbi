defmodule Bilimbi.Base.Settings.ContributionValidator do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Settings.Definition

  @impl true
  def validate_contributions!(entries) when is_list(entries) do
    entries
    |> Enum.reduce(%{definitions: %{}, runtime_claims: %{}}, &merge_entry!/2)
    |> Map.update!(:runtime_claims, &(Map.keys(&1) |> Enum.sort()))
  end

  defp merge_entry!(%{descriptor: descriptor, payload: payload}, snapshot)
       when is_map(payload) do
    allowed_keys = [:definitions, :runtime_claims]
    unknown_keys = Map.keys(payload) -- allowed_keys

    if unknown_keys != [] do
      raise ArgumentError,
            "settings contribution from #{descriptor.id} has unknown keys: " <>
              Enum.map_join(Enum.sort(unknown_keys), ", ", &inspect/1)
    end

    definitions = Map.get(payload, :definitions, %{})
    runtime_claims = Map.get(payload, :runtime_claims, [])

    unless is_map(definitions),
      do: raise(ArgumentError, "settings definitions from #{descriptor.id} must be a map")

    unless is_list(runtime_claims),
      do: raise(ArgumentError, "settings runtime claims from #{descriptor.id} must be a list")

    snapshot
    |> merge_definitions!(descriptor.id, definitions)
    |> merge_runtime_claims!(descriptor.id, runtime_claims)
  end

  defp merge_entry!(%{descriptor: descriptor}, _snapshot) do
    raise ArgumentError, "settings contribution from #{descriptor.id} must be a map"
  end

  defp merge_definitions!(snapshot, owner, definitions) do
    resolved =
      Map.new(definitions, fn
        {key, attributes} when is_binary(key) -> {key, Definition.new!(key, owner, attributes)}
        {key, _attributes} -> raise ArgumentError, "setting key #{inspect(key)} must be a string"
      end)

    duplicates =
      resolved
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(snapshot.definitions)))
      |> MapSet.to_list()

    if duplicates != [] do
      raise ArgumentError,
            "settings definitions have duplicate ownership: #{Enum.join(Enum.sort(duplicates), ", ")}"
    end

    %{snapshot | definitions: Map.merge(snapshot.definitions, resolved)}
  end

  defp merge_runtime_claims!(snapshot, owner, claims) do
    claims =
      Map.new(claims, fn
        claim when is_binary(claim) and claim != "" ->
          {claim, owner}

        claim ->
          raise ArgumentError, "runtime setting claim #{inspect(claim)} from #{owner} is invalid"
      end)

    duplicates =
      claims
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(snapshot.runtime_claims)))
      |> MapSet.to_list()

    if duplicates != [] do
      raise ArgumentError,
            "runtime setting claims have duplicate ownership: #{Enum.join(Enum.sort(duplicates), ", ")}"
    end

    %{snapshot | runtime_claims: Map.merge(snapshot.runtime_claims, claims)}
  end
end
