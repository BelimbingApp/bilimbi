defmodule Bilimbi.Base.Audit.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:base_audit_mutations, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :company_id, :bigint
      add :tenant_id, :bigint
      add :actor_type, :string, size: 40, null: false
      add :actor_id, :bigint, null: false
      add :actor_role, :string, size: 100
      add :ip_address, :inet
      add :url, :text
      add :user_agent, :string, size: 80
      add :auditable_type, :string, size: 255, null: false
      add :auditable_id, :string, size: 128, null: false
      add :subject_name, :string, size: 255
      add :subject_id, :string, size: 128
      add :subject_identifier, :string, size: 255
      add :source, :string, size: 20, null: false, default: "listener"
      add :event, :string, size: 20, null: false
      add :old_values, :jsonb
      add :new_values, :jsonb
      add :trace_id, :string, size: 12
      add :occurred_at, :naive_datetime, null: false
    end

    create index(:base_audit_mutations, [:company_id])
    create index(:base_audit_mutations, [:tenant_id])
    create index(:base_audit_mutations, [:actor_type])
    create index(:base_audit_mutations, [:actor_id])
    create index(:base_audit_mutations, [:auditable_type])
    create index(:base_audit_mutations, [:auditable_id])
    create index(:base_audit_mutations, [:source])
    create index(:base_audit_mutations, [:event])
    create index(:base_audit_mutations, [:trace_id])
    create index(:base_audit_mutations, [:occurred_at])

    create index(:base_audit_mutations, [:auditable_type, :auditable_id, :occurred_at],
             name: :base_audit_mutations_auditable_occurred_index
           )

    create index(:base_audit_mutations, [:actor_type, :actor_id, :occurred_at])

    create index(
             :base_audit_mutations,
             [:subject_name, :subject_id, :subject_identifier, :occurred_at],
             name: :base_audit_mutations_subject_idx,
             where: "subject_name IS NOT NULL"
           )

    create table(:base_audit_actions, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :company_id, :bigint
      add :tenant_id, :bigint
      add :actor_type, :string, size: 40, null: false
      add :actor_id, :bigint, null: false
      add :actor_role, :string, size: 100
      add :ip_address, :inet
      add :url, :text
      add :user_agent, :string, size: 80
      add :event, :string, size: 255, null: false
      add :payload, :jsonb
      add :trace_id, :string, size: 12
      add :is_retained, :boolean, null: false, default: false
      add :occurred_at, :naive_datetime, null: false
    end

    create index(:base_audit_actions, [:company_id])
    create index(:base_audit_actions, [:tenant_id])
    create index(:base_audit_actions, [:actor_type])
    create index(:base_audit_actions, [:actor_id])
    create index(:base_audit_actions, [:event])
    create index(:base_audit_actions, [:trace_id])
    create index(:base_audit_actions, [:occurred_at])
    create index(:base_audit_actions, [:event, :occurred_at])
    create index(:base_audit_actions, [:actor_type, :actor_id, :occurred_at])
  end

  def down do
    drop table(:base_audit_actions)
    drop table(:base_audit_mutations)
  end
end
