defmodule Bilimbi.Core.User.Migrations.AddUserAccountForeignKeyIndexes do
  use Ecto.Migration

  def change do
    create(index(:users, [:company_id], name: :users_company_id_index))
    create(index(:users, [:employee_id], name: :users_employee_id_index))
  end
end
