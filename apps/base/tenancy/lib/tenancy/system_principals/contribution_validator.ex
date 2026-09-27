defmodule Bilimbi.Base.Tenancy.SystemPrincipals.ContributionValidator do
  @moduledoc """
  Validates `:system_principals` contributions into one map keyed by name.

  Each contribution is a list of `%{name:, description:, capabilities:}`
  maps. A name is dot-separated lowercase segments with at least one dot,
  such as `coating.line_import`, and belongs to exactly one module: a second
  declaration of the same name, from any module, is a defect. Capability
  keys are checked for shape here; Base Authz refuses a key it does not know
  when one is granted or evaluated.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  @name_pattern ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/
  @capability_pattern ~r/^[a-z0-9][a-z0-9_.-]*$/
  @max_name_bytes 100
  @max_capability_bytes 255
  @keys [:capabilities, :description, :name]

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: map()
  def validate_contributions!(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn %{descriptor: descriptor, payload: payload}, acc ->
      unless is_list(payload) do
        invalid!(descriptor.id, "expected a list of principal declarations")
      end

      Enum.reduce(payload, acc, fn declaration, acc ->
        principal = validate_principal!(descriptor, declaration)

        case Map.fetch(acc, principal.name) do
          {:ok, existing} ->
            invalid!(
              descriptor.id,
              "#{inspect(principal.name)} is already declared by #{existing.module_id}"
            )

          :error ->
            Map.put(acc, principal.name, principal)
        end
      end)
    end)
  end

  defp validate_principal!(descriptor, %{} = declaration) do
    unless declaration |> Map.keys() |> Enum.sort() == @keys do
      invalid!(descriptor.id, "a declaration has exactly the keys #{inspect(@keys)}")
    end

    %{name: name, description: description, capabilities: capabilities} = declaration

    unless is_binary(name) and byte_size(name) <= @max_name_bytes and name =~ @name_pattern do
      invalid!(descriptor.id, "#{inspect(name)} is not a dot-separated lowercase name")
    end

    unless is_binary(description) and String.trim(description) != "" do
      invalid!(descriptor.id, "#{name} needs a description")
    end

    unless is_list(capabilities) and Enum.all?(capabilities, &capability?/1) and
             capabilities == Enum.uniq(capabilities) do
      invalid!(descriptor.id, "#{name} capabilities must be distinct lowercase capability keys")
    end

    %{
      name: name,
      description: description,
      capabilities: Enum.sort(capabilities),
      module_id: descriptor.id,
      otp_app: descriptor.otp_app
    }
  end

  defp validate_principal!(descriptor, _declaration),
    do: invalid!(descriptor.id, "a declaration must be a map")

  defp capability?(key),
    do: is_binary(key) and byte_size(key) <= @max_capability_bytes and key =~ @capability_pattern

  defp invalid!(id, message) do
    raise ArgumentError, "invalid system_principals contribution from #{id}: #{message}"
  end
end
