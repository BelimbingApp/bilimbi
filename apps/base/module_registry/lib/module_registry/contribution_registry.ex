defmodule Bilimbi.Base.ModuleRegistry.ContributionRegistry do
  @moduledoc """
  Builds and publishes one validated contribution snapshot for a deployment.

  Providers are discovered exclusively from Mix-approved installed descriptor
  metadata. Each provider executes once per build, and every consumer validates
  its complete provenance-carrying entry list before the snapshot is installed.
  """

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.ModuleRegistry.ContributionConsumer
  alias Bilimbi.Base.ModuleRegistry.ContributionProvider

  @snapshot_key {__MODULE__, :snapshot}
  @consumer_validators %{
    settings: Bilimbi.Base.Settings.ContributionValidator,
    authz: Bilimbi.Base.Authz.ContributionValidator,
    menu: Bilimbi.Base.Menu.ContributionValidator
  }
  @consumer_keys @consumer_validators |> Map.keys() |> Enum.sort()

  @type snapshot :: %{
          graph_fingerprint: String.t() | nil,
          consumers: %{required(atom()) => term()}
        }

  @spec install!() :: snapshot()
  def install! do
    case :persistent_term.get(@snapshot_key, :missing) do
      :missing ->
        snapshot = build!()
        :persistent_term.put(@snapshot_key, snapshot)
        snapshot

      snapshot ->
        snapshot
    end
  end

  @spec build!([map()]) :: snapshot()
  def build!(modules \\ ModuleRegistry.installed_modules!()) when is_list(modules) do
    entries = Enum.reduce(modules, empty_entries(), &collect_provider!/2)

    consumers =
      Map.new(@consumer_keys, fn consumer ->
        {consumer, validate_consumer!(consumer, Map.fetch!(entries, consumer))}
      end)

    snapshot = %{
      graph_fingerprint: modules |> List.first() |> then(&(&1 && &1.graph_fingerprint)),
      consumers: consumers
    }

    unless plain_term?(snapshot) do
      raise ArgumentError, "validated contribution snapshot contains a non-plain term"
    end

    snapshot
  end

  @spec snapshot!() :: snapshot()
  def snapshot! do
    case :persistent_term.get(@snapshot_key, :missing) do
      :missing ->
        raise ArgumentError,
              "module contribution snapshot is not installed; start the deployment application first"

      snapshot ->
        snapshot
    end
  end

  @spec consumer!(atom()) :: term()
  def consumer!(consumer) when consumer in @consumer_keys do
    snapshot!().consumers |> Map.fetch!(consumer)
  end

  @doc false
  @spec put_snapshot_for_test!(snapshot()) :: snapshot()
  def put_snapshot_for_test!(snapshot) when is_map(snapshot) do
    unless plain_term?(snapshot),
      do: raise(ArgumentError, "test snapshot must contain plain terms")

    :persistent_term.put(@snapshot_key, snapshot)
    snapshot
  end

  @doc false
  def clear_for_test! do
    :persistent_term.erase(@snapshot_key)
    :ok
  end

  defp empty_entries, do: Map.new(@consumer_keys, &{&1, []})

  defp collect_provider!(%{contribution_provider: nil}, entries), do: entries

  defp collect_provider!(%{contribution_provider: provider} = descriptor, entries) do
    validate_provider!(descriptor, provider)
    payload = invoke_provider!(descriptor, provider)

    unless is_map(payload) do
      raise ArgumentError,
            "contribution provider #{inspect(provider)} for #{descriptor.id} must return a map"
    end

    unknown_keys = Map.keys(payload) -- @consumer_keys

    if unknown_keys != [] do
      raise ArgumentError,
            "contribution provider #{inspect(provider)} for #{descriptor.id} returned unknown keys: " <>
              Enum.map_join(Enum.sort(unknown_keys), ", ", &inspect/1)
    end

    unless plain_term?(payload) do
      raise ArgumentError,
            "contribution provider #{inspect(provider)} for #{descriptor.id} returned a non-plain term"
    end

    Enum.reduce(payload, entries, fn {consumer, consumer_payload}, acc ->
      Map.update!(acc, consumer, &(&1 ++ [%{descriptor: descriptor, payload: consumer_payload}]))
    end)
  end

  defp validate_provider!(descriptor, provider) do
    unless Code.ensure_loaded?(provider) do
      raise ArgumentError,
            "contribution provider #{inspect(provider)} for #{descriptor.id} could not be loaded"
    end

    behaviours =
      provider.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    unless ContributionProvider in behaviours and function_exported?(provider, :contributions, 0) do
      raise ArgumentError,
            "contribution provider #{inspect(provider)} for #{descriptor.id} must implement " <>
              inspect(ContributionProvider)
    end

    application_modules = Application.spec(descriptor.otp_app, :modules) || []

    unless provider in application_modules do
      raise ArgumentError,
            "contribution provider #{inspect(provider)} does not belong to #{descriptor.otp_app} " <>
              "for #{descriptor.id}"
    end
  end

  defp invoke_provider!(descriptor, provider) do
    provider.contributions()
  rescue
    error ->
      reraise ArgumentError,
              [
                message:
                  "contribution provider #{inspect(provider)} for #{descriptor.id} failed: " <>
                    Exception.message(error)
              ],
              __STACKTRACE__
  end

  defp validate_consumer!(_consumer, []), do: []

  defp validate_consumer!(consumer, entries) do
    validator = Map.fetch!(@consumer_validators, consumer)

    unless Code.ensure_loaded?(validator) do
      raise ArgumentError,
            "#{consumer} contributions exist but validator #{inspect(validator)} is not installed"
    end

    behaviours =
      validator.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    unless ContributionConsumer in behaviours and
             function_exported?(validator, :validate_contributions!, 1) do
      raise ArgumentError,
            "contribution validator #{inspect(validator)} must implement " <>
              inspect(ContributionConsumer)
    end

    apply(validator, :validate_contributions!, [entries])
  end

  defp plain_term?(term)
       when is_nil(term) or is_boolean(term) or is_number(term) or is_binary(term) or
              is_atom(term),
       do: true

  defp plain_term?(term) when is_list(term), do: Enum.all?(term, &plain_term?/1)

  defp plain_term?(term) when is_tuple(term) do
    term |> Tuple.to_list() |> Enum.all?(&plain_term?/1)
  end

  defp plain_term?(term) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.all?(fn {key, value} -> plain_term?(key) and plain_term?(value) end)
  end

  defp plain_term?(_term), do: false
end
