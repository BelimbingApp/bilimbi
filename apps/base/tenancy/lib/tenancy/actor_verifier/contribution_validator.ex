defmodule Bilimbi.Base.Tenancy.ActorVerifier.ContributionValidator do
  @moduledoc """
  Validates `:actor_verifier` contributions into the one installed verifier.

  A second verifier is a defect: whether a queued job may still act for a
  user must not depend on installation order. No contribution validates to
  `nil`, and delegated jobs then refuse to run.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Tenancy.ActorVerifier

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: module() | nil
  def validate_contributions!([]), do: nil

  def validate_contributions!([%{descriptor: descriptor, payload: verifier}]),
    do: validate_verifier!(descriptor, verifier)

  def validate_contributions!(entries) when is_list(entries) do
    ids = Enum.map_join(entries, ", ", & &1.descriptor.id)
    raise ArgumentError, "invalid actor_verifier contribution: more than one verifier from #{ids}"
  end

  defp validate_verifier!(descriptor, verifier) do
    unless is_atom(verifier) and not is_nil(verifier) and Code.ensure_loaded?(verifier) do
      invalid!(descriptor.id, "verifier #{inspect(verifier)} could not be loaded")
    end

    behaviours =
      verifier.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    unless ActorVerifier in behaviours do
      invalid!(descriptor.id, "#{inspect(verifier)} does not implement #{inspect(ActorVerifier)}")
    end

    unless verifier in (Application.spec(descriptor.otp_app, :modules) || []) do
      invalid!(
        descriptor.id,
        "verifier #{inspect(verifier)} does not belong to #{inspect(descriptor.otp_app)}"
      )
    end

    verifier
  end

  defp invalid!(id, message) do
    raise ArgumentError, "invalid actor_verifier contribution from #{id}: #{message}"
  end
end
