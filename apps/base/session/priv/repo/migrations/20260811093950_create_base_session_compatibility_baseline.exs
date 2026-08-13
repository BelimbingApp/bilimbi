defmodule Bilimbi.Base.Session.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:user_id, :bigint)
      add(:ip_address, :string, size: 45)
      add(:user_agent, :text)
      add(:payload, :text, null: false)
      add(:last_activity, :integer, null: false)
    end

    create(index(:sessions, [:user_id], name: :sessions_user_id_index))
    create(index(:sessions, [:last_activity], name: :sessions_last_activity_index))
  end
end
