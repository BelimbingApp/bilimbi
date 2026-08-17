defmodule Bilimbi.Base.Authz.DecisionLogSummary do
  @moduledoc """
  Stable payload-safe read model for one authorization decision log.

  Deliberately carries actor identity as `actor_type` + `actor_id` and does not
  include mutable display names. This keeps the audit read model stable and
  payload-safe while avoiding a Base-to-Core naming join at read time.
  """

  alias Bilimbi.Base.Authz.DecisionLog

  @enforce_keys [:id, :actor_type, :actor_id, :capability, :allowed, :reason, :occurred_at]
  defstruct [
    :id,
    :company_id,
    :actor_type,
    :actor_id,
    :acting_for_user_id,
    :capability,
    :resource_type,
    :resource_id,
    :allowed,
    :reason,
    :trace_id,
    :occurred_at
  ]

  @type t :: %__MODULE__{}

  @doc false
  @spec from_schema(DecisionLog.t()) :: t()
  def from_schema(%DecisionLog{} = log) do
    %__MODULE__{
      id: log.id,
      company_id: log.company_id,
      actor_type: log.actor_type,
      actor_id: log.actor_id,
      acting_for_user_id: log.acting_for_user_id,
      capability: log.capability,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      allowed: log.allowed,
      reason: log.reason_code,
      trace_id: log.trace_id,
      occurred_at: log.occurred_at
    }
  end
end
