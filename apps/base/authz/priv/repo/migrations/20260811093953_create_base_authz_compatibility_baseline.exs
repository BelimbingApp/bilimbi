defmodule Bilimbi.Base.Authz.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:base_authz_roles, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:company_id, :bigint)
      add(:name, :string, null: false)
      add(:code, :string, null: false)
      add(:description, :text)
      add(:is_system, :boolean, null: false, default: false)
      add(:grant_all, :boolean, null: false, default: false)
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create(index(:base_authz_roles, [:company_id], name: :base_authz_roles_company_id_index))

    create(
      unique_index(:base_authz_roles, [:company_id, :code],
        name: :base_authz_roles_company_id_code_unique
      )
    )

    create table(:base_authz_role_capabilities, primary_key: false) do
      add(:id, :bigserial, primary_key: true)

      add(
        :role_id,
        references(:base_authz_roles,
          type: :bigint,
          on_delete: :delete_all,
          name: :base_authz_role_capabilities_role_id_foreign
        ),
        null: false
      )

      add(:capability_key, :string, null: false)
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create(
      unique_index(:base_authz_role_capabilities, [:role_id, :capability_key],
        name: :base_authz_role_capabilities_role_id_capability_key_unique
      )
    )

    create(
      index(:base_authz_role_capabilities, [:capability_key],
        name: :base_authz_role_capabilities_capability_key_index
      )
    )

    create table(:base_authz_principal_roles, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:company_id, :bigint)
      add(:principal_type, :string, size: 40, null: false)
      add(:principal_id, :bigint, null: false)

      add(
        :role_id,
        references(:base_authz_roles,
          type: :bigint,
          on_delete: :delete_all,
          name: :base_authz_principal_roles_role_id_foreign
        ),
        null: false
      )

      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create(
      index(:base_authz_principal_roles, [:company_id],
        name: :base_authz_principal_roles_company_id_index
      )
    )

    create(
      index(:base_authz_principal_roles, [:principal_type, :principal_id],
        name: :base_authz_principal_roles_principal_type_principal_id_index
      )
    )

    create(
      unique_index(
        :base_authz_principal_roles,
        [:company_id, :principal_type, :principal_id, :role_id],
        name: :base_authz_principal_roles_unique
      )
    )

    create table(:base_authz_principal_capabilities, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:company_id, :bigint)
      add(:principal_type, :string, size: 40, null: false)
      add(:principal_id, :bigint, null: false)
      add(:capability_key, :string, null: false)
      add(:is_allowed, :boolean, null: false, default: true)
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create(
      index(:base_authz_principal_capabilities, [:company_id],
        name: :base_authz_principal_capabilities_company_id_index
      )
    )

    create(
      index(:base_authz_principal_capabilities, [:principal_type, :principal_id],
        name: :base_authz_principal_caps_principal_index
      )
    )

    create(
      index(:base_authz_principal_capabilities, [:capability_key],
        name: :base_authz_principal_capabilities_capability_key_index
      )
    )

    create(
      unique_index(
        :base_authz_principal_capabilities,
        [:company_id, :principal_type, :principal_id, :capability_key],
        name: :base_authz_principal_caps_unique
      )
    )

    create table(:base_authz_decision_logs, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:company_id, :bigint)
      add(:actor_type, :string, size: 40, null: false)
      add(:actor_id, :bigint, null: false)
      add(:acting_for_user_id, :bigint)
      add(:capability, :string, null: false)
      add(:resource_type, :string)
      add(:resource_id, :string)
      add(:allowed, :boolean, null: false)
      add(:reason_code, :string, null: false)
      add(:applied_policies, :json)
      add(:context, :json)
      add(:trace_id, :string, size: 12)
      add(:occurred_at, :naive_datetime, null: false)
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    for column <- [
          :company_id,
          :actor_type,
          :actor_id,
          :acting_for_user_id,
          :capability,
          :resource_type,
          :resource_id,
          :allowed,
          :reason_code,
          :trace_id,
          :occurred_at
        ] do
      create(index(:base_authz_decision_logs, [column]))
    end

    create(index(:base_authz_decision_logs, [:actor_type, :actor_id, :occurred_at]))
    create(index(:base_authz_decision_logs, [:capability, :allowed]))
  end

  def down do
    drop(table(:base_authz_decision_logs))
    drop(table(:base_authz_principal_capabilities))
    drop(table(:base_authz_principal_roles))
    drop(table(:base_authz_role_capabilities))
    drop(table(:base_authz_roles))
  end
end
