defmodule Bilimbi.Core.User.Migrations.AddUserAccountForeignKeyIndexes do
  use Ecto.Migration

  # Part of the compatible baseline: Belimbing's `create_users_table` indexes
  # both account references, so every adopted database already has these two
  # and adoption records this version without running it. A fresh database
  # creates them here.
  def change do
    create(index(:users, [:company_id], name: :users_company_id_index))
    create(index(:users, [:employee_id], name: :users_employee_id_index))
  end
end
