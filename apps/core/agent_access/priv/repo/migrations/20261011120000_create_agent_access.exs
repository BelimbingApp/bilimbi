defmodule Bilimbi.Core.AgentAccess.Migrations.CreateAgentAccess do
  use Ecto.Migration

  def change do
    create table(:core_agent_connections) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :company_id, references(:companies, on_delete: :restrict), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :agent_id, :string, null: false
      add :seen_agent_ids, :map, null: false, default: %{}
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:core_agent_connections, [:tenant_id, :user_id])

    create table(:core_agent_devices) do
      add :device_hash, :binary, null: false
      add :user_hash, :binary, null: false
      add :client_id, :string, null: false
      add :agent_id, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :next_poll_at, :utc_datetime, null: false
      add :interval, :integer, null: false
      add :status, :string, null: false
      add :connection_id, references(:core_agent_connections, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:core_agent_devices, [:device_hash])
    create unique_index(:core_agent_devices, [:user_hash])

    create table(:core_agent_tokens) do
      add :connection_id, references(:core_agent_connections, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :kind, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:core_agent_tokens, [:token_hash])
  end
end
