defmodule Bilimbi.Base.Repo.Migrations.CreateBaseTenancyCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:tenants, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :parent_id, :bigint
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :is_platform_operator, :boolean, null: false, default: false
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
      add :deleted_at, :naive_datetime
    end

    create index(:tenants, [:parent_id])
    create index(:tenants, [:status])
    create index(:tenants, [:parent_id, :status])

    create unique_index(:tenants, [:is_platform_operator],
             name: :tenants_one_platform_operator,
             where: "is_platform_operator = TRUE"
           )
  end

  def down do
    drop table(:tenants)
  end
end
