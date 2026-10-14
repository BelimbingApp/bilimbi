defmodule Bilimbi.Core.AgentAccess.Connection do
  @moduledoc false
  use Ecto.Schema

  schema "core_agent_connections" do
    field :tenant_id, :integer
    field :company_id, :integer
    field :user_id, :integer
    field :agent_id, :string
    field :client_id, :string, default: "bilimbi-native"
    field :resource, :string
    field :oauth_scope, :string
    field :seen_agent_ids, :map
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
