defmodule Bilimbi.Base.AgentApi.Reach do
  @moduledoc """
  Which capabilities an operation may stand on, and which of them a scope
  reaches.

  A capability's verb decides whether it reads: `view`, `list` and `search`
  do, and every other verb, an unknown one included, is a write. A read
  operation must stand on a read capability, so an agent connected to read
  can never be handed a write by a mislabelled operation.

  The access-control capabilities are never an agent's: role, grant,
  field-restriction and system-principal administration (`admin.authz.`),
  impersonation, settings management (`base.settings.`), and the management
  of agent connections (`admin.agent-connection.`). No operation may stand
  on one, so an agent can never widen its own reach or anyone else's.

  `capabilities/1` is what a scope reaches: its person's live allows, read
  afresh on every call as `Bilimbi.Base.Authz.effective_capabilities/1`
  reads them. A scope that names no person reaches nothing. Loading the
  allows once writes no decision-log rows, so search can ask it freely;
  `Bilimbi.Base.AgentApi.call/3` still asks `Authz.can/4` for the one
  capability it runs on.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.CapabilityKey
  alias Bilimbi.Base.Tenancy.Scope

  @read_verbs ~w(view list search)
  @access_control_prefixes ~w(admin.authz. admin.agent-connection. base.settings.)
  @access_control_keys ~w(admin.user.impersonate)

  @doc "The verbs a read capability ends in."
  @spec read_verbs() :: [String.t()]
  def read_verbs, do: @read_verbs

  @doc "Whether `capability` is a well-formed key ending in a read verb."
  @spec read?(String.t()) :: boolean()
  def read?(capability) when is_binary(capability) do
    CapabilityKey.valid?(capability) and CapabilityKey.parse!(capability).action in @read_verbs
  end

  @doc "Whether `capability` controls access, so no agent may ever hold it."
  @spec access_control?(String.t()) :: boolean()
  def access_control?(capability) when is_binary(capability) do
    capability in @access_control_keys or
      String.starts_with?(capability, @access_control_prefixes)
  end

  @doc "The capabilities the scope's person holds now, without the access-control set."
  @spec capabilities(Scope.t()) :: MapSet.t(String.t())
  def capabilities(%Scope{} = scope) do
    case Authz.scope_actor(scope) do
      {:ok, actor} ->
        actor
        |> Authz.effective_capabilities()
        |> Map.fetch!(:allowed)
        |> Enum.reject(&access_control?/1)
        |> MapSet.new()

      {:error, :no_authenticated_actor} ->
        MapSet.new()
    end
  end
end
