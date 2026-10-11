defmodule Bilimbi.Base.Authz.AgentPolicy do
  @moduledoc false
  alias Bilimbi.Base.Authz.CapabilityKey
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope
  @read_verbs ~w(view list search)
  @access_control_prefixes ~w(admin.authz. admin.agent-connection. base.settings.)
  @access_control_keys ~w(admin.user.impersonate)
  def read_verbs, do: @read_verbs

  def read?(key),
    do: CapabilityKey.valid?(key) and CapabilityKey.parse!(key).action in @read_verbs

  def access_control?(key),
    do: key in @access_control_keys or String.starts_with?(key, @access_control_prefixes)

  # Dispatch limits writes to installed preview/commit operations. Authz keeps
  # the person's grants and the company switch; it never owns an API registry.
  def refusal(scope, key, platform_capabilities) do
    if Scope.actor(scope).facet do
      cond do
        key in platform_capabilities -> :denied_agent_platform
        access_control?(key) -> :denied_agent_access_control
        not read?(key) and not writes_enabled?(scope) -> :denied_agent_writes_off
        true -> nil
      end
    end
  end

  @doc "The signed-in company's switch, read afresh on preview and commit."
  def writes_enabled?(%Scope{} = scope) do
    actor = Scope.actor(scope)
    writes_enabled_in_company?(scope, actor.company_id)
  end

  def writes_enabled_in_company?(%Scope{} = scope, company_id) do
    Settings.get(
      "authz.agent_writes_enabled",
      SettingsScope.company(company_id, Scope.tenant_id(scope))
    )
  end
end
