defmodule Bilimbi.Base.AgentApi.Plan do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  def __audit_redacted_fields__, do: [:binding_hash, :operations_hash, :preview_hash]

  schema "base_agent_api_plans" do
    field :tenant_id, :id
    field :binding_hash, :binary
    field :operations_hash, :binary
    field :preview_hash, :binary
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
  end
end
