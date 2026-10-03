defmodule Bilimbi.Base.Workflow.Migrations.CreateHumanActionCompatibilityBaseline do
  use Ecto.Migration

  def change do
    schema = Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(prefix() || "public")

    create table(:base_workflow_human_action_requests, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:tenant_id, :bigint, null: false)
      add(:idempotency_key, :string, null: false)
      add(:intent_hash, :char, size: 64, null: false)
      add(:action_key, :string, null: false)
      add(:subject_type, :string, null: false)
      add(:subject_id, :string, null: false)
      add(:process_run_id, :bigint)
      add(:work_item_id, :bigint)
      add(:actor_type, :string, null: false)
      add(:actor_id, :bigint, null: false)
      add(:result, :json)
      add(:completed_at, :naive_datetime, precision: 0)
      add(:created_at, :naive_datetime, precision: 0)
      add(:updated_at, :naive_datetime, precision: 0)
    end

    execute(
      ~s|ALTER TABLE #{schema}."base_workflow_human_action_requests" ADD CONSTRAINT "base_workflow_human_request_unique" UNIQUE ("tenant_id", "idempotency_key")|,
      ~s|ALTER TABLE #{schema}."base_workflow_human_action_requests" DROP CONSTRAINT "base_workflow_human_request_unique"|
    )

    create(
      index(:base_workflow_human_action_requests, [:tenant_id, :subject_type, :subject_id],
        name: :base_workflow_human_subject_idx
      )
    )
  end
end
