defmodule Bilimbi.Base.PrincipalDirectory.ContributionValidator do
  @moduledoc """
  Validates principal-directory contributions into one provider per kind.

  Unlike the dashboard's widget list, a second provider for the same kind is a
  defect rather than an addition: two modules claiming to name users would make
  which name a screen shows depend on installation order.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.PrincipalDirectory.Provider

  @kinds [:user, :agent, :employee]

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: %{
          Provider.kind() => module()
        }
  def validate_contributions!(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, &merge_entry!/2)
  end

  # A module contributes one provider (a module atom) or several (a list of
  # them), one per kind — Core Employee names both `:agent` and `:employee`
  # (ADR 0014). A second provider for the same kind, from any module, is still a
  # defect: which name a screen shows must not depend on installation order.
  defp merge_entry!(%{descriptor: descriptor, payload: payload}, acc) do
    payload
    |> providers!(descriptor)
    |> Enum.reduce(acc, &merge_provider!(descriptor, &1, &2))
  end

  defp providers!(provider, _descriptor) when is_atom(provider) and not is_nil(provider),
    do: [provider]

  defp providers!(providers, descriptor) when is_list(providers) and providers != [] do
    Enum.each(providers, fn provider ->
      unless is_atom(provider) and not is_nil(provider) do
        invalid!(
          descriptor.id,
          "principal_directory list entries must be module atoms, got #{inspect(provider)}"
        )
      end
    end)

    providers
  end

  defp providers!(payload, descriptor) do
    invalid!(
      descriptor.id,
      "principal_directory must be a module atom or a non-empty list of them, got #{inspect(payload)}"
    )
  end

  defp merge_provider!(descriptor, provider, acc) do
    kind = validate_provider!(descriptor, provider)

    case Map.fetch(acc, kind) do
      {:ok, existing} ->
        invalid!(
          descriptor.id,
          "provider #{inspect(provider)} claims kind #{inspect(kind)} already claimed by #{inspect(existing)}"
        )

      :error ->
        Map.put(acc, kind, provider)
    end
  end

  defp validate_provider!(descriptor, provider) do
    unless Code.ensure_loaded?(provider) do
      invalid!(descriptor.id, "provider #{inspect(provider)} could not be loaded")
    end

    behaviours =
      provider.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    unless Provider in behaviours do
      invalid!(descriptor.id, "provider #{inspect(provider)} does not implement #{inspect(Provider)}")
    end

    # The owning package must be the contributing one. Without this a module
    # could nominate somebody else's implementation and the graph would not show
    # the edge.
    application_modules = Application.spec(descriptor.otp_app, :modules) || []

    unless provider in application_modules do
      invalid!(
        descriptor.id,
        "provider #{inspect(provider)} does not belong to #{inspect(descriptor.otp_app)}"
      )
    end

    kind = provider.principal_kind()

    unless kind in @kinds do
      invalid!(descriptor.id, "provider #{inspect(provider)} declares unknown kind #{inspect(kind)}")
    end

    kind
  end

  defp invalid!(id, message) do
    raise ArgumentError, "invalid principal_directory contribution from #{id}: #{message}"
  end
end
