defmodule Bilimbi.Base.Settings.Authorization do
  @moduledoc """
  Whether the sealed scope may change a platform-global setting.

  Base Settings defines the question and gains no dependency on whoever
  answers it. Base Authz already depends on Settings, so the reverse edge
  would be a cycle. The workspace wires the answer in
  `:bilimbi_base_settings, :authorization`. A missing or unloaded answer
  refuses the change.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @callback can?(Scope.t(), String.t()) :: boolean()

  @doc """
  Whether `scope` holds `capability` right now.

  The configured module is asked only when it is loaded. Otherwise the answer
  is no, so a package test or a miswired release cannot change a global setting.
  """
  @spec can?(Scope.t(), String.t()) :: boolean()
  def can?(%Scope{} = scope, capability) when is_binary(capability) do
    case Application.get_env(:bilimbi_base_settings, :authorization) do
      module when is_atom(module) and not is_nil(module) ->
        Code.ensure_loaded?(module) and module.can?(scope, capability)

      _missing ->
        false
    end
  end
end
