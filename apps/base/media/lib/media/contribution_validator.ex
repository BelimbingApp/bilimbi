defmodule Bilimbi.Base.Media.ContributionValidator do
  @moduledoc """
  Validates attachment authorizers with their descriptor provenance.

  One owner controls each stable subject and all its legacy aliases. Adapters
  must be compiled in the contributing application and declare the policy
  behavior. Registration is immutable and duplicates fail at installation.
  """
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer
  alias Bilimbi.Base.Media.AttachmentSubjectAuthorizer

  @impl true
  def validate_contributions!(entries), do: Enum.reduce(entries, %{}, &collect!/2)

  defp collect!(%{descriptor: descriptor, payload: %{subjects: subjects} = payload}, registry)
       when is_list(subjects) and map_size(payload) == 1 do
    unless "base/media" in descriptor.dependencies,
      do: invalid!("#{descriptor.id} must declare base/media")

    Enum.reduce(subjects, registry, fn entry, acc ->
      unless is_map(entry) and not is_struct(entry) and
               Map.keys(entry) -- [:key, :adapter, :aliases] == [],
             do: invalid!("invalid subject entry")

      key = Map.get(entry, :key)
      aliases = Map.get(entry, :aliases, [])
      adapter = Map.get(entry, :adapter)

      unless is_binary(key) and Regex.match?(~r/\A[a-z][a-z0-9_.-]*\z/, key) and
               byte_size(key) <= 255,
             do: invalid!("invalid stable subject key")

      unless is_list(aliases) and
               Enum.all?(aliases, &(is_binary(&1) and &1 != "" and byte_size(&1) <= 255)),
             do: invalid!("invalid aliases")

      unless is_atom(adapter) and adapter not in [nil, true, false] and
               Code.ensure_loaded?(adapter) and
               adapter in (Application.spec(descriptor.otp_app, :modules) || []),
             do: invalid!("adapter must belong to #{descriptor.id}")

      behaviours =
        adapter.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      unless AttachmentSubjectAuthorizer in behaviours and
               function_exported?(adapter, :authorize, 4),
             do: invalid!("adapter must implement AttachmentSubjectAuthorizer")

      Enum.reduce([key | aliases], acc, fn name, acc ->
        if Map.has_key?(acc, name), do: invalid!("duplicate subject #{name}")
        Map.put(acc, name, %{key: key, adapter: adapter, owner: descriptor.id})
      end)
    end)
  end

  defp collect!(_entry, _registry), do: invalid!("expected subjects list")
  defp invalid!(reason), do: raise(ArgumentError, "invalid media contribution: #{reason}")
end
