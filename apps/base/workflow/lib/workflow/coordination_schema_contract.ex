defmodule Bilimbi.Base.Workflow.CoordinationSchemaContract do
  @moduledoc false

  def tables do
    [
      %{
        name: "base_workflow_process_definition_versions",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_process_definition_versions_id_seq"}
          },
          "definition_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "definition_version" => %{type: :integer, nullable: false, default: nil},
          "definition_fingerprint" => %{type: {:char, 64}, nullable: false, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_process_definition_version_unique" => %{
            columns: ["definition_key", "definition_version"],
            unique: true,
            where: nil
          },
          "base_workflow_process_definition_versions_pkey" => %{
            columns: ["id"],
            unique: true,
            where: nil
          }
        },
        foreign_keys: %{},
        checks: %{}
      },
      %{
        name: "base_workflow_process_dependencies",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_process_dependencies_id_seq"}
          },
          "work_item_id" => %{type: :bigint, nullable: false, default: nil},
          "depends_on_work_item_id" => %{type: :bigint, nullable: false, default: nil},
          "acceptable_outcomes" => %{type: :json, nullable: false, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "tenant_id" => %{type: :bigint, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_dependency_tenant_idx" => %{
            columns: ["tenant_id"],
            unique: false,
            where: nil
          },
          "base_workflow_process_dependencies_pkey" => %{
            columns: ["id"],
            unique: true,
            where: nil
          },
          "base_workflow_process_dependency_unique" => %{
            columns: ["work_item_id", "depends_on_work_item_id"],
            unique: true,
            where: nil
          }
        },
        foreign_keys: %{
          "base_workflow_process_dependencies_work_item_id_foreign" => %{
            columns: ["work_item_id"],
            references: {"base_workflow_process_work_items", ["id"]},
            on_delete: :cascade,
            on_update: :nothing
          },
          "wf_dep_depends_fk" => %{
            columns: ["depends_on_work_item_id"],
            references: {"base_workflow_process_work_items", ["id"]},
            on_delete: :cascade,
            on_update: :nothing
          }
        },
        checks: %{}
      },
      %{
        name: "base_workflow_process_events",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_process_events_id_seq"}
          },
          "process_run_id" => %{type: :bigint, nullable: false, default: nil},
          "work_item_id" => %{type: :bigint, nullable: true, default: nil},
          "sequence" => %{type: :bigint, nullable: false, default: nil},
          "type" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "payload" => %{type: :json, nullable: true, default: nil},
          "idempotency_key" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "occurred_at" => %{type: {:timestamp, 0}, nullable: false, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "tenant_id" => %{type: :bigint, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_event_tenant_time_idx" => %{
            columns: ["tenant_id", "occurred_at"],
            unique: false,
            where: nil
          },
          "base_workflow_process_event_sequence_unique" => %{
            columns: ["process_run_id", "sequence"],
            unique: true,
            where: nil
          },
          "base_workflow_process_event_timeline_idx" => %{
            columns: ["process_run_id", "occurred_at"],
            unique: false,
            where: nil
          },
          "base_workflow_process_events_idempotency_key_unique" => %{
            columns: ["idempotency_key"],
            unique: true,
            where: nil
          },
          "base_workflow_process_events_pkey" => %{columns: ["id"], unique: true, where: nil}
        },
        foreign_keys: %{
          "base_workflow_process_events_process_run_id_foreign" => %{
            columns: ["process_run_id"],
            references: {"base_workflow_process_runs", ["id"]},
            on_delete: :cascade,
            on_update: :nothing
          },
          "base_workflow_process_events_work_item_id_foreign" => %{
            columns: ["work_item_id"],
            references: {"base_workflow_process_work_items", ["id"]},
            on_delete: :nilify_all,
            on_update: :nothing
          }
        },
        checks: %{}
      },
      %{
        name: "base_workflow_process_runs",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_process_runs_id_seq"}
          },
          "definition_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "definition_version" => %{type: :integer, nullable: false, default: nil},
          "definition_fingerprint" => %{type: {:char, 64}, nullable: false, default: nil},
          "status" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "priority" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "subject_type" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "subject_id" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "correlation_key" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "input" => %{type: :json, nullable: true, default: nil},
          "output" => %{type: :json, nullable: true, default: nil},
          "idempotency_key" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "last_error" => %{type: :text, nullable: true, default: nil},
          "started_at" => %{type: {:timestamp, 0}, nullable: false, default: nil},
          "available_at" => %{type: {:timestamp, 0}, nullable: false, default: nil},
          "heartbeat_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "paused_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "pause_reason" => %{type: :text, nullable: true, default: nil},
          "completed_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "scope_type" => %{
            type: {:varchar, 16},
            nullable: false,
            default: {:string, "unresolved"}
          },
          "tenant_id" => %{type: :bigint, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_process_correlation_idx" => %{
            columns: ["correlation_key"],
            unique: false,
            where: nil
          },
          "base_workflow_process_definition_idx" => %{
            columns: ["definition_key", "definition_version"],
            unique: false,
            where: nil
          },
          "base_workflow_process_runs_idempotency_key_unique" => %{
            columns: ["idempotency_key"],
            unique: true,
            where: nil
          },
          "base_workflow_process_runs_pkey" => %{columns: ["id"], unique: true, where: nil},
          "base_workflow_process_scope_idx" => %{
            columns: ["scope_type", "tenant_id"],
            unique: false,
            where: nil
          },
          "base_workflow_process_status_idx" => %{
            columns: ["status", "available_at", "priority"],
            unique: false,
            where: nil
          },
          "base_workflow_process_subject_idx" => %{
            columns: ["subject_type", "subject_id"],
            unique: false,
            where: nil
          }
        },
        foreign_keys: %{},
        checks: %{}
      },
      %{
        name: "base_workflow_process_work_items",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_process_work_items_id_seq"}
          },
          "process_run_id" => %{type: :bigint, nullable: false, default: nil},
          "step_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "label" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "executor_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "status" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "dependency_mode" => %{type: {:varchar, 3}, nullable: false, default: {:string, "all"}},
          "required_signal" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "signalled_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "signal_payload" => %{type: :json, nullable: true, default: nil},
          "delay_seconds" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "available_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "attempts" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "max_attempts" => %{type: :integer, nullable: false, default: {:integer, 1}},
          "priority" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "lease_owner" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "lease_token" => %{type: {:varchar, 64}, nullable: true, default: nil},
          "lease_expires_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "heartbeat_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "outcome" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "input" => %{type: :json, nullable: true, default: nil},
          "input_ref" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "output" => %{type: :json, nullable: true, default: nil},
          "result_ref" => %{type: {:varchar, 255}, nullable: true, default: nil},
          "metadata" => %{type: :json, nullable: true, default: nil},
          "last_error" => %{type: :text, nullable: true, default: nil},
          "completed_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "tenant_id" => %{type: :bigint, nullable: true, default: nil},
          "version" => %{type: :integer, nullable: false, default: {:integer, 1}}
        },
        indexes: %{
          "base_workflow_process_step_unique" => %{
            columns: ["process_run_id", "step_key"],
            unique: true,
            where: nil
          },
          "base_workflow_process_work_items_lease_token_unique" => %{
            columns: ["lease_token"],
            unique: true,
            where: nil
          },
          "base_workflow_process_work_items_pkey" => %{columns: ["id"], unique: true, where: nil},
          "base_workflow_work_available_idx" => %{
            columns: ["status", "available_at"],
            unique: false,
            where: nil
          },
          "base_workflow_work_lease_idx" => %{
            columns: ["lease_expires_at"],
            unique: false,
            where: nil
          },
          "base_workflow_work_priority_idx" => %{
            columns: ["status", "priority", "available_at"],
            unique: false,
            where: nil
          },
          "base_workflow_work_tenant_status_idx" => %{
            columns: ["tenant_id", "status"],
            unique: false,
            where: nil
          }
        },
        foreign_keys: %{
          "base_workflow_process_work_items_process_run_id_foreign" => %{
            columns: ["process_run_id"],
            references: {"base_workflow_process_runs", ["id"]},
            on_delete: :cascade,
            on_update: :nothing
          }
        },
        checks: %{}
      },
      %{
        name: "base_workflow_transition_outbox",
        columns: %{
          "id" => %{
            type: :bigint,
            nullable: false,
            default: {:sequence, "base_workflow_transition_outbox_id_seq"}
          },
          "event_key" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "event_type" => %{type: {:varchar, 255}, nullable: false, default: nil},
          "payload" => %{type: :json, nullable: false, default: nil},
          "attempts" => %{type: :integer, nullable: false, default: {:integer, 0}},
          "available_at" => %{type: {:timestamp, 0}, nullable: false, default: nil},
          "lease_token" => %{type: {:varchar, 64}, nullable: true, default: nil},
          "lease_expires_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "delivered_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "last_error" => %{type: :text, nullable: true, default: nil},
          "created_at" => %{type: {:timestamp, 0}, nullable: true, default: nil},
          "updated_at" => %{type: {:timestamp, 0}, nullable: true, default: nil}
        },
        indexes: %{
          "base_workflow_outbox_due_idx" => %{
            columns: ["delivered_at", "available_at"],
            unique: false,
            where: nil
          },
          "base_workflow_outbox_lease_idx" => %{
            columns: ["lease_expires_at"],
            unique: false,
            where: nil
          },
          "base_workflow_transition_outbox_event_key_unique" => %{
            columns: ["event_key"],
            unique: true,
            where: nil
          },
          "base_workflow_transition_outbox_lease_token_unique" => %{
            columns: ["lease_token"],
            unique: true,
            where: nil
          },
          "base_workflow_transition_outbox_pkey" => %{columns: ["id"], unique: true, where: nil}
        },
        foreign_keys: %{},
        checks: %{}
      }
    ]
  end
end
