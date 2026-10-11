defmodule Bilimbi.Core.AgentAccess.Device do
  @moduledoc false
  use Ecto.Schema
  @derive {Inspect, except: [:id, :device_hash, :user_hash]}
  schema "core_agent_devices" do
    field :device_hash, :binary
    field :user_hash, :binary
    field :client_id, :string
    field :agent_id, :string
    field :expires_at, :utc_datetime
    field :next_poll_at, :utc_datetime
    field :interval, :integer
    field :status, :string
    field :connection_id, :integer
    timestamps(type: :utc_datetime)
  end

  def __audit_redacted_fields__, do: [:device_hash, :user_hash]
end
