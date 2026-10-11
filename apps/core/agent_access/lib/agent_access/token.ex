defmodule Bilimbi.Core.AgentAccess.Token do
  @moduledoc false
  use Ecto.Schema
  @derive {Inspect, except: [:id, :token_hash]}
  schema "core_agent_tokens" do
    field :connection_id, :integer
    field :token_hash, :binary
    field :kind, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def __audit_redacted_fields__, do: [:token_hash]
end
