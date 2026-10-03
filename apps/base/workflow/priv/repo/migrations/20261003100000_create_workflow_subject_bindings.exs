defmodule Bilimbi.Base.Workflow.Migrations.CreateSubjectBindings do
  use Ecto.Migration

  def change do
    create table(:base_workflow_subject_bindings) do
      add :tenant_id, references(:tenants, type: :bigint, on_delete: :restrict), null: false
      add :flow, :string, null: false
      add :flow_id, :bigint, null: false
      add :subject_type, :string, null: false
      add :subject_id, :string, null: false
      add :owner, :string, null: false
      add :created_at, :naive_datetime, precision: 0, null: false
    end

    create unique_index(:base_workflow_subject_bindings, [:flow, :flow_id],
             name: :base_workflow_subject_binding_unique
           )

    create unique_index(:base_workflow_subject_bindings, [:tenant_id, :subject_type, :subject_id],
             name: :base_workflow_subject_identity_unique
           )
  end
end
