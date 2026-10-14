defmodule Bilimbi.Core.AgentAccess.Migrations.AddMcpOAuth do
  use Ecto.Migration

  def change do
    alter table(:core_agent_connections) do
      add(:client_id, :string, null: false, default: "bilimbi-native")
      add(:resource, :text)
      add(:oauth_scope, :string)
    end

    create table(:core_agent_authorization_codes) do
      add(:connection_id, references(:core_agent_connections, on_delete: :delete_all),
        null: false
      )

      add(:code_hash, :binary, null: false)
      add(:code_challenge, :string, null: false)
      add(:redirect_uri, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:used_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:core_agent_authorization_codes, [:code_hash]))
  end
end
