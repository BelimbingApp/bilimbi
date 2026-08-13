defmodule Bilimbi.Base.Session.Entry do
  @moduledoc "Stable read model for one stored session, including its opaque payload."

  alias Bilimbi.Base.Session.Schema

  @enforce_keys [:id, :payload, :last_activity]
  defstruct [:id, :user_id, :ip_address, :user_agent, :payload, :last_activity]

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: pos_integer() | nil,
          ip_address: String.t() | nil,
          user_agent: String.t() | nil,
          payload: String.t(),
          last_activity: non_neg_integer()
        }

  @doc false
  @spec from_schema(Schema.t()) :: t()
  def from_schema(%Schema{} = session) do
    %__MODULE__{
      id: session.id,
      user_id: session.user_id,
      ip_address: session.ip_address,
      user_agent: session.user_agent,
      payload: session.payload,
      last_activity: session.last_activity
    }
  end
end
