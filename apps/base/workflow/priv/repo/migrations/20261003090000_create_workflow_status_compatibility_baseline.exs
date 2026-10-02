defmodule Bilimbi.Base.Workflow.Migrations.CreateStatusCompatibilityBaseline do
  use Ecto.Migration

  def change do
    schema = Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(prefix() || "public")

    create table(:base_workflow, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :code, :string, null: false
      add :label, :string, null: false
      add :module, :string
      add :description, :text
      add :model_class, :string
      add :settings, :json
      add :is_active, :boolean, null: false, default: true
      add :created_at, :naive_datetime, precision: 0
      add :updated_at, :naive_datetime, precision: 0
    end

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow" ADD CONSTRAINT "base_workflow_code_unique" UNIQUE ("code")|,
      ~s|ALTER TABLE #{schema}."base_workflow" DROP CONSTRAINT "base_workflow_code_unique"|
    )

    create table(:base_workflow_kanban_columns, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flow, :string, null: false
      add :code, :string, null: false
      add :label, :string, null: false
      add :position, :integer, null: false, default: 0
      add :wip_limit, :integer
      add :settings, :json
      add :description, :text
      add :is_active, :boolean, null: false, default: true
      add :created_at, :naive_datetime, precision: 0
      add :updated_at, :naive_datetime, precision: 0
    end

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_kanban_columns" ADD CONSTRAINT "base_workflow_kanban_columns_flow_code_unique" UNIQUE ("flow", "code")|,
      ~s|ALTER TABLE #{schema}."base_workflow_kanban_columns" DROP CONSTRAINT "base_workflow_kanban_columns_flow_code_unique"|
    )

    create index(:base_workflow_kanban_columns, [:flow, :is_active, :position],
             name: :base_workflow_kanban_columns_flow_is_active_position_index
           )

    create table(:base_workflow_status_configs, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flow, :string, null: false
      add :code, :string, null: false
      add :label, :string, null: false
      add :pic, :json
      add :notifications, :json
      add :position, :integer, null: false, default: 0
      add :comment_tags, :json
      add :prompt, :text
      add :kanban_code, :string
      add :is_active, :boolean, null: false, default: true
      add :created_at, :naive_datetime, precision: 0
      add :updated_at, :naive_datetime, precision: 0
    end

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_status_configs" ADD CONSTRAINT "base_workflow_status_configs_flow_code_unique" UNIQUE ("flow", "code")|,
      ~s|ALTER TABLE #{schema}."base_workflow_status_configs" DROP CONSTRAINT "base_workflow_status_configs_flow_code_unique"|
    )

    create index(:base_workflow_status_configs, [:flow],
             name: :base_workflow_status_configs_flow_index
           )

    create index(:base_workflow_status_configs, [:flow, :is_active, :position],
             name: :base_workflow_status_configs_flow_is_active_position_index
           )

    create table(:base_workflow_status_history, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flow, :string, null: false
      add :flow_id, :bigint, null: false
      add :status, :string, null: false
      add :tat, :integer
      add :actor_id, :bigint
      add :actor_role, :string
      add :actor_department, :string
      add :actor_company, :string
      add :assignees, :json
      add :comment, :text
      add :comment_tag, :string
      add :attachments, :json
      add :metadata, :json
      add :transitioned_at, :naive_datetime, null: false, precision: 0
      add :created_at, :naive_datetime, precision: 0
      add :actor_type, :string
    end

    create index(:base_workflow_status_history, [:actor_id],
             name: :base_workflow_status_history_actor_id_index
           )

    create index(:base_workflow_status_history, [:flow, :flow_id, :transitioned_at],
             name: :idx_flow_lookup
           )

    create index(:base_workflow_status_history, [:flow, :status, :transitioned_at],
             name: :idx_flow_status
           )

    create index(:base_workflow_status_history, [:flow, :status, :tat], name: :idx_tat_sla)

    create table(:base_workflow_status_transitions, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flow, :string, null: false
      add :from_code, :string, null: false
      add :to_code, :string, null: false
      add :label, :string
      add :capability, :string
      add :guard_class, :string
      add :action_class, :string
      add :sla_seconds, :integer
      add :metadata, :json
      add :position, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true
      add :created_at, :naive_datetime, precision: 0
      add :updated_at, :naive_datetime, precision: 0
    end

    create index(:base_workflow_status_transitions, [:flow, :from_code, :is_active],
             name: :base_workflow_status_transitions_flow_from_code_is_active_index
           )

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_status_transitions" ADD CONSTRAINT "base_workflow_status_transitions_flow_from_code_to_code_unique" UNIQUE ("flow", "from_code", "to_code")|,
      ~s|ALTER TABLE #{schema}."base_workflow_status_transitions" DROP CONSTRAINT "base_workflow_status_transitions_flow_from_code_to_code_unique"|
    )
  end
end
