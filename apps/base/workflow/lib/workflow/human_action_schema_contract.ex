defmodule Bilimbi.Base.Workflow.HumanActionSchemaContract do
  @moduledoc false

  def tables do
    [
      %{
        name: "base_workflow_human_action_requests",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_human_action_requests_id_seq"}
          },
          "tenant_id" => %{type: :bigint, nullable: false, default: nil},
          "idempotency_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "intent_hash" => %{type: {:char, 64}, nullable: false, default: nil},
          "action_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "subject_type" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "subject_id" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "process_run_id" => %{type: :bigint, nullable: true, default: nil},
          "work_item_id" => %{type: :bigint, nullable: true, default: nil},
          "actor_type" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "actor_id" => %{type: :bigint, nullable: false, default: nil},
          "result" => %{type: :json, nullable: true, default: nil},
          "completed_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_human_action_requests_pkey" => %{
            columns: ["id"],
            unique: true,
            where: nil
          },
          "base_workflow_human_request_unique" => %{
            columns: ["tenant_id", "idempotency_key"],
            unique: true,
            where: nil
          },
          "base_workflow_human_subject_idx" => %{
            columns: ["tenant_id", "subject_type", "subject_id"],
            unique: false,
            where: nil
          }
        },
        foreign_keys: %{},
        checks: %{}
      }
    ]
  end
end
