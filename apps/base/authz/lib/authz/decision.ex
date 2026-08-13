defmodule Bilimbi.Base.Authz.Decision do
  @moduledoc "Stable authorization outcome with a machine-readable reason and policy trail."

  @type reason ::
          :allowed
          | :denied_unknown_capability
          | :denied_invalid_actor_context
          | :denied_tenant_scope
          | :denied_company_scope
          | :denied_missing_capability
          | :denied_explicitly
          | :denied_policy_engine_error

  @enforce_keys [:allowed, :reason]
  defstruct [:allowed, :reason, policies: [], audit_meta: %{}]

  @type t :: %__MODULE__{
          allowed: boolean(),
          reason: reason(),
          policies: [String.t()],
          audit_meta: map()
        }

  @spec allow([String.t()], map()) :: t()
  def allow(policies \\ [], audit_meta \\ %{}) do
    %__MODULE__{allowed: true, reason: :allowed, policies: policies, audit_meta: audit_meta}
  end

  @spec deny(reason(), [String.t()], map()) :: t()
  def deny(reason, policies \\ [], audit_meta \\ %{}) do
    %__MODULE__{allowed: false, reason: reason, policies: policies, audit_meta: audit_meta}
  end
end
