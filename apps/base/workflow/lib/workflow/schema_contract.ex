defmodule Bilimbi.Base.Workflow.SchemaContract do
  @moduledoc "Pinned status-table structure; unbound historical rows are preserved, never guessed."
  @behaviour Bilimbi.Base.Database.SchemaContract

  @impl true
  def verify_invariants(repo, opts), do: Bilimbi.Base.Workflow.SchemaInvariants.verify(repo, opts)

  @impl true
  def tables do
    [
      %{
        name: "base_workflow",
        columns: %{
          "id" => %{type: :bigint, nullable: false, default: {:sequence, "base_workflow_id_seq"}},
          "code" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "label" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "module" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "description" => %{type: :text, nullable: true, default: nil},
          "model_class" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "settings" => %{type: :json, nullable: true, default: nil},
          "is_active" => %{type: :boolean, nullable: false, default: {:boolean, true}},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_code_unique" => %{columns: ["code"], unique: true, where: nil},
          "base_workflow_pkey" => %{columns: ["id"], unique: true, where: nil}
        },
        foreign_keys: %{},
        checks: %{}
      },
      %{
        name: "base_workflow_kanban_columns",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_kanban_columns_id_seq"}
          },
          "flow" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "code" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "label" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "position" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "wip_limit" => %{type: :integer, nullable: true, default: nil},
          "settings" => %{type: :json, nullable: true, default: nil},
          "description" => %{type: :text, nullable: true, default: nil},
          "is_active" => %{type: :boolean, nullable: false, default: {:boolean, true}},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_kanban_columns_flow_code_unique" => %{
            columns: ["flow", "code"],
            unique: true,
            where: nil
          },
          "base_workflow_kanban_columns_flow_is_active_position_index" => %{
            columns: ["flow", "is_active", "position"],
            unique: false,
            where: nil
          },
          "base_workflow_kanban_columns_pkey" => %{columns: ["id"], unique: true, where: nil}
        },
        foreign_keys: %{},
        checks: %{}
      },
      %{
        name: "base_workflow_status_configs",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_status_configs_id_seq"}
          },
          "flow" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "code" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "label" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "pic" => %{type: :json, nullable: true, default: nil},
          "notifications" => %{type: :json, nullable: true, default: nil},
          "position" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "comment_tags" => %{type: :json, nullable: true, default: nil},
          "prompt" => %{type: :text, nullable: true, default: nil},
          "kanban_code" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "is_active" => %{type: :boolean, nullable: false, default: {:boolean, true}},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_status_configs_flow_code_unique" => %{
            columns: ["flow", "code"],
            unique: true,
            where: nil
          },
          "base_workflow_status_configs_flow_index" => %{
            columns: ["flow"],
            unique: false,
            where: nil
          },
          "base_workflow_status_configs_flow_is_active_position_index" => %{
            columns: ["flow", "is_active", "position"],
            unique: false,
            where: nil
          },
          "base_workflow_status_configs_pkey" => %{columns: ["id"], unique: true, where: nil}
        },
        foreign_keys: %{},
        checks: %{}
      },
      %{
        name: "base_workflow_status_history",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_status_history_id_seq"}
          },
          "flow" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "flow_id" => %{type: :bigint, nullable: false, default: nil},
          "status" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "tat" => %{type: :integer, nullable: true, default: nil},
          "actor_id" => %{type: :bigint, nullable: true, default: nil},
          "actor_role" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "actor_department" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "actor_company" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "assignees" => %{type: :json, nullable: true, default: nil},
          "comment" => %{type: :text, nullable: true, default: nil},
          "comment_tag" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "attachments" => %{type: :json, nullable: true, default: nil},
          "metadata" => %{type: :json, nullable: true, default: nil},
          "transitioned_at" => %{type: {:timestamp, 0}, nullable: false, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "actor_type" => %{type: {:varchar, 255}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_status_history_actor_id_index" => %{
            columns: ["actor_id"],
            unique: false,
            where: nil
          },
          "base_workflow_status_history_pkey" => %{columns: ["id"], unique: true, where: nil},
          "idx_flow_lookup" => %{
            columns: ["flow", "flow_id", "transitioned_at"],
            unique: false,
            where: nil
          },
          "idx_flow_status" => %{
            columns: ["flow", "status", "transitioned_at"],
            unique: false,
            where: nil
          },
          "idx_tat_sla" => %{columns: ["flow", "status", "tat"], unique: false, where: nil}
        },
        foreign_keys: %{},
        checks: %{}
      },
      %{
        name: "base_workflow_status_transitions",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_status_transitions_id_seq"}
          },
          "flow" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "from_code" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "to_code" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "label" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "capability" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "guard_class" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "action_class" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "sla_seconds" => %{type: :integer, nullable: true, default: nil},
          "metadata" => %{type: :json, nullable: true, default: nil},
          "position" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "is_active" => %{type: :boolean, nullable: false, default: {:boolean, true}},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_status_transitions_flow_from_code_is_active_index" => %{
            columns: ["flow", "from_code", "is_active"],
            unique: false,
            where: nil
          },
          "base_workflow_status_transitions_flow_from_code_to_code_unique" => %{
            columns: ["flow", "from_code", "to_code"],
            unique: true,
            where: nil
          },
          "base_workflow_status_transitions_pkey" => %{columns: ["id"], unique: true, where: nil}
        },
        foreign_keys: %{},
        checks: %{}
      }
    ]
  end
end
