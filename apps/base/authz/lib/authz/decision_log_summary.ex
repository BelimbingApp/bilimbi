defmodule Bilimbi.Base.Authz.DecisionLogSummary do
  @moduledoc """
  Stable payload-safe read model for one authorization decision log.

  Actor identity is `actor_type` + `actor_id` only. Display names are omitted
  on purpose:

  * Base must not join Core User or Employee schemas.
  * The durable row records ids (`Bilimbi.Base.Authz.DatabaseDecisionLogger`),
    not a denormalised name that would drift after rename.
  * Belimbing's admin index left-joins `users` for **user** principals only
    (`app/Base/Authz/Livewire/DecisionLogs/Index.php`, `where actor_type =
    PrincipalType::USER`). Employee/agent rows stay unnamed there too, so
    copying that join would still be incomplete and would couple Base to Core.

  A later naming seam would be a directory callback spanning User and Employee
  (the same shape as `Bilimbi.Base.Authz.CompanyDirectory` / #183), not a field
  on this struct. See #185.
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
