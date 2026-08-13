defmodule Bilimbi.Base.Audit.Action do
  @moduledoc """
  Stable read model for a recorded action.

  Callers receive this struct, never the private Ecto schema.
  """

  alias Bilimbi.Base.Audit.ActionSchema

  @enforce_keys [:id, :actor_type, :actor_id, :event, :occurred_at]
  defstruct [
    :id,
    :company_id,
    :tenant_id,
    :actor_type,
    :actor_id,
    :actor_role,
    :ip_address,
    :url,
    :user_agent,
    :event,
    :payload,
    :trace_id,
    :is_retained,
    :occurred_at
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil,
          actor_type: String.t(),
          actor_id: integer(),
          actor_role: String.t() | nil,
          ip_address: Postgrex.INET.t() | nil,
          url: String.t() | nil,
          user_agent: String.t() | nil,
          event: String.t(),
          payload: map() | list() | nil,
          trace_id: String.t() | nil,
          is_retained: boolean(),
          occurred_at: NaiveDateTime.t()
        }

  @doc false
  @spec from_schema(ActionSchema.t()) :: t()
  def from_schema(%ActionSchema{} = action) do
    %__MODULE__{
      id: action.id,
      company_id: action.company_id,
      tenant_id: action.tenant_id,
      actor_type: action.actor_type,
      actor_id: action.actor_id,
      actor_role: action.actor_role,
      ip_address: action.ip_address,
      url: action.url,
      user_agent: action.user_agent,
      event: action.event,
      payload: action.payload,
      trace_id: action.trace_id,
      is_retained: action.is_retained,
      occurred_at: action.occurred_at
    }
  end
end
