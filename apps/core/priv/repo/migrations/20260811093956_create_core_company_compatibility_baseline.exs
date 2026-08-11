defmodule Bilimbi.Core.Migrations.CreateCoreCompanyCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:companies, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :parent_id, :bigint
      add :name, :string, null: false
      add :code, :string, null: false
      add :status, :string, null: false, default: "active"
      add :legal_name, :string
      add :registration_number, :string
      add :tax_id, :string
      add :legal_entity_type_id, :bigint
      add :jurisdiction, :string
      add :email, :string
      add :website, :string
      add :scope_activities, :json
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
      add :deleted_at, :naive_datetime
      add :tenant_id,
          references(:tenants,
            type: :bigint,
            on_delete: :restrict,
            name: :companies_tenant_foreign
          ),
          null: false
    end

    create index(:companies, [:parent_id])
    create unique_index(:companies, [:code], name: :companies_code_unique)
    create index(:companies, [:status])
    create index(:companies, [:legal_entity_type_id])
    create index(:companies, [:parent_id, :status])
    create index(:companies, [:created_at])
    create index(:companies, [:tenant_id])
    create unique_index(:companies, [:id, :tenant_id], name: :companies_id_tenant_unique)

    execute(
      """
      ALTER TABLE #{qualified_table("companies")}
      ADD CONSTRAINT companies_parent_tenant_foreign
      FOREIGN KEY (parent_id, tenant_id)
      REFERENCES #{qualified_table("companies")} (id, tenant_id)
      ON DELETE RESTRICT
      """,
      """
      ALTER TABLE #{qualified_table("companies")}
      DROP CONSTRAINT companies_parent_tenant_foreign
      """
    )

    create table(:tenant_primary_companies, primary_key: false) do
      add :tenant_id,
          references(:tenants,
            type: :bigint,
            on_delete: :restrict,
            name: :tenant_primary_companies_tenant_foreign
          ),
          primary_key: true

      add :company_id, :bigint, null: false
    end

    create unique_index(:tenant_primary_companies, [:company_id],
             name: :tenant_primary_companies_company_id_unique
           )

    execute(
      """
      ALTER TABLE #{qualified_table("tenant_primary_companies")}
      ADD CONSTRAINT tenant_primary_companies_company_tenant_foreign
      FOREIGN KEY (company_id, tenant_id)
      REFERENCES #{qualified_table("companies")} (id, tenant_id)
      ON DELETE RESTRICT
      """,
      """
      ALTER TABLE #{qualified_table("tenant_primary_companies")}
      DROP CONSTRAINT tenant_primary_companies_company_tenant_foreign
      """
    )

    create table(:company_relationship_types, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :is_external, :boolean, null: false, default: false
      add :is_active, :boolean, null: false, default: true
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:company_relationship_types, [:code],
             name: :company_relationship_types_code_unique
           )
    create index(:company_relationship_types, [:is_active, :code])

    create table(:company_relationships, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :company_id,
          references(:companies,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_relationships_company_id_foreign
          ),
          null: false

      add :related_company_id,
          references(:companies,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_relationships_related_company_id_foreign
          ),
          null: false

      add :relationship_type_id,
          references(:company_relationship_types,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_relationships_relationship_type_id_foreign
          ),
          null: false

      add :effective_from, :date
      add :effective_to, :date
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
      add :deleted_at, :naive_datetime
    end

    create index(:company_relationships, [:company_id, :relationship_type_id])

    create index(:company_relationships, [:related_company_id, :relationship_type_id],
             name: :company_relationships_related_type_index
           )

    create index(:company_relationships, [:effective_from, :effective_to])

    create unique_index(
             :company_relationships,
             [:company_id, :related_company_id, :relationship_type_id, :effective_from],
             name: :company_relationship_unique
           )

    create table(:company_external_accesses, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :company_id,
          references(:companies,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_external_accesses_company_id_foreign
          ),
          null: false

      add :relationship_id,
          references(:company_relationships,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_external_accesses_relationship_id_foreign
          ),
          null: false

      add :permissions, :json
      add :is_active, :boolean, null: false, default: true
      add :access_granted_at, :naive_datetime
      add :access_expires_at, :naive_datetime
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
      add :deleted_at, :naive_datetime
    end

    create index(:company_external_accesses, [:company_id, :is_active])
    create index(:company_external_accesses, [:access_expires_at])

    create table(:company_legal_entity_types, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :is_active, :boolean, null: false, default: true
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:company_legal_entity_types, [:code],
             name: :company_legal_entity_types_code_unique
           )
    create index(:company_legal_entity_types, [:is_active, :code])

    create table(:company_department_types, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :category, :string, null: false
      add :description, :text
      add :is_active, :boolean, null: false, default: true
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:company_department_types, [:code],
             name: :company_department_types_code_unique
           )
    create index(:company_department_types, [:category])
    create index(:company_department_types, [:is_active, :category])

    create table(:company_departments, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :company_id,
          references(:companies,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_departments_company_id_foreign
          ),
          null: false

      add :department_type_id,
          references(:company_department_types,
            type: :bigint,
            on_delete: :delete_all,
            name: :company_departments_department_type_id_foreign
          ),
          null: false

      add :head_id, :bigint
      add :status, :string, null: false, default: "active"
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create index(:company_departments, [:head_id])
    create index(:company_departments, [:status])
    create unique_index(:company_departments, [:company_id, :department_type_id],
             name: :company_departments_company_id_department_type_id_unique
           )
  end

  def down do
    drop table(:company_departments)
    drop table(:company_department_types)
    drop table(:company_legal_entity_types)
    drop table(:company_external_accesses)
    drop table(:company_relationships)
    drop table(:company_relationship_types)
    drop table(:tenant_primary_companies)
    drop table(:companies)
  end

  defp qualified_table(table) do
    [prefix() || "public", table]
    |> Enum.map_join(".", &quote_identifier/1)
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
