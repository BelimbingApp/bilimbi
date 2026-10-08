defmodule Bilimbi.Core.User.Migrations.AddUserAccountForeignKeyIndexes do
  use Ecto.Migration

  # Belimbing's `create_users_table` already indexes both account references
  # under these names, so an adopted database has them and a fresh Bilimbi
  # database does not. Create each only when absent.
  def change do
    create_if_not_exists(index(:users, [:company_id], name: :users_company_id_index))
    create_if_not_exists(index(:users, [:employee_id], name: :users_employee_id_index))
  end
end
