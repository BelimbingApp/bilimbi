defmodule Bilimbi.Base.Authz.AgentPolicy do
  @moduledoc false
  alias Bilimbi.Base.Authz.CapabilityKey
  alias Bilimbi.Base.Tenancy.Scope
  @read_verbs ~w(view list search)
  @access_control_prefixes ~w(admin.authz. admin.agent-connection. base.settings.)
  @access_control_keys ~w(admin.user.impersonate)
  def read_verbs, do: @read_verbs

  def read?(key),
    do: CapabilityKey.valid?(key) and CapabilityKey.parse!(key).action in @read_verbs

  def access_control?(key),
    do: key in @access_control_keys or String.starts_with?(key, @access_control_prefixes)

  # The read-only door disables every write. Safe writes will add the company's
  # configured switch here; discovery and dispatch use this same policy.
  def refusal(scope, key, platform_capabilities) do
    if Scope.actor(scope).facet do
      cond do
        key in platform_capabilities -> :denied_agent_platform
        access_control?(key) -> :denied_agent_access_control
        not read?(key) -> :denied_agent_writes_off
        true -> nil
      end
    end
  end
end
