defmodule Bilimbi.Base.Authz.Migrations.CreateFieldRestrictions do
  @moduledoc """
  Bilimbi-only: field access restrictions an operator sets at runtime.

  A restriction names one field of one catalog table (`Bilimbi.Base.Grid`'s
  table and field ids, such as `companies` / `email`) in one tenant, and the
  roles that may still see it. Everyone else in the tenant reads the field
  as restricted on the record page, in grid columns, in the audit views, and
  may not write it. Which roles see the field is the join table: deleting a
  role or a restriction removes its rows. The restriction rows themselves
  are audited like every write through the repo, and Base Authz records a
  retained `authz.field_restriction.set` / `.removed` action naming who
  changed what.
  """

  use Ecto.Migration

  def change do
    create table(:base_authz_field_restrictions) do
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :table_id, :string, size: 100, null: false
      add :field_id, :string, size: 100, null: false
      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create unique_index(:base_authz_field_restrictions, [:tenant_id, :table_id, :field_id],
             name: :base_authz_field_restrictions_unique
           )

    create table(:base_authz_field_restriction_roles) do
      add :restriction_id, references(:base_authz_field_restrictions, on_delete: :delete_all),
        null: false

      add :role_id, references(:base_authz_roles, on_delete: :delete_all), null: false
      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create unique_index(:base_authz_field_restriction_roles, [:restriction_id, :role_id],
             name: :base_authz_field_restriction_roles_unique
           )

    create index(:base_authz_field_restriction_roles, [:role_id])
  end
end
