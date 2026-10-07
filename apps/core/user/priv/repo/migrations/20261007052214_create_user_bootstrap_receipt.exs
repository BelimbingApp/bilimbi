defmodule Bilimbi.Core.User.Migrations.CreateUserBootstrapReceipt do
  use Ecto.Migration

  def change do
    create table(:bilimbi_user_bootstrap, primary_key: false) do
      add(:id, :bigint, primary_key: true)
      add(:tenant_name, :string, null: false)
      add(:company_name, :string, null: false)
      add(:company_code, :string, null: false)
      add(:admin_email, :string, null: false)
      # A receipt survives deletion of the account or changes to its company.
      # These are historical identities, deliberately not foreign keys.
      add(:user_id, :bigint, null: false)
      add(:company_id, :bigint, null: false)
      add(:tenant_id, :bigint, null: false)
      add(:completed_at, :naive_datetime, null: false)
    end

    create(
      constraint(:bilimbi_user_bootstrap, :bilimbi_user_bootstrap_singleton, check: "id = 1")
    )
  end
end
