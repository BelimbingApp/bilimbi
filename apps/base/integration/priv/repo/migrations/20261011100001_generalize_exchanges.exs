defmodule Bilimbi.Base.Integration.Migrations.GeneralizeExchanges do
  use Ecto.Migration

  def change do
    # Preserve the durable relation name and existing outgoing records.
    alter table(:base_integration_outbound_exchanges) do
      add(:direction, :string, size: 10, null: false, default: "outgoing")
      add(:method, :string, size: 16)
      add(:host, :string)
      add(:path, :text)
      add(:person_id, :bigint)
      add(:impersonator_id, :bigint)
      add(:connection_id, :string)
      add(:agent_id, :string)
      add(:run_id, :string)
    end

    create(
      constraint(:base_integration_outbound_exchanges, :integration_exchange_direction,
        check: "direction = 'incoming' OR direction = 'outgoing'"
      )
    )

    create(
      index(
        :base_integration_outbound_exchanges,
        [:tenant_id, :direction, :occurred_at, :id],
        name: :integration_exchange_timeline
      )
    )
  end
end
