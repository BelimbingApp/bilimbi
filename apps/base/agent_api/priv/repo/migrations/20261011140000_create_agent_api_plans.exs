defmodule Bilimbi.Base.AgentApi.Migrations.CreateAgentApiPlans do
  use Ecto.Migration
  def change do
    create table(:base_agent_api_plans, primary_key: false) do
      add :id, :string, size: 64, primary_key: true
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :binding_hash, :binary, null: false
      add :operations_hash, :binary, null: false
      add :preview_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
    end
    create index(:base_agent_api_plans, [:expires_at])
  end
end
