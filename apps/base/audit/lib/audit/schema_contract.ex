defmodule Bilimbi.Base.Audit.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Base Audit compatibility baseline.

  The `impersonator_id` column and its partial index on both tables are the
  Bilimbi-only impersonation contribution (migration `20260914090000`). They
  are declared as an optional group: an adopted Belimbing database verifies
  without them, a migrated Bilimbi database verifies with them, and a table
  carrying only half of the pair is drift.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_813_114_300

  def migration_version, do: @migration_version

  @impl true
  def tables, do: [mutations(), actions()]

  defp mutations do
    %{
      name: "base_audit_mutations",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_audit_mutations_id_seq"}),
        "company_id" => column(:bigint),
        "tenant_id" => column(:bigint),
        "actor_type" => column({:varchar, 40}, false),
        "actor_id" => column(:bigint, false),
        "actor_role" => column({:varchar, 100}),
        "ip_address" => column(:inet),
        "url" => column(:text),
        "user_agent" => column({:varchar, 80}),
        "auditable_type" => column({:varchar, 255}, false),
        "auditable_id" => column({:varchar, 128}, false),
        "subject_name" => column({:varchar, 255}),
        "subject_id" => column({:varchar, 128}),
        "subject_identifier" => column({:varchar, 255}),
        "source" => column({:varchar, 20}, false, {:string, "listener"}),
        "event" => column({:varchar, 20}, false),
        "old_values" => column(:jsonb),
        "new_values" => column(:jsonb),
        "trace_id" => column({:varchar, 12}),
        "occurred_at" => column({:timestamp, 0}, false)
      },
      indexes: %{
        "base_audit_mutations_pkey" => index(["id"], true),
        "base_audit_mutations_company_id_index" => index(["company_id"]),
        "base_audit_mutations_tenant_id_index" => index(["tenant_id"]),
        "base_audit_mutations_actor_type_index" => index(["actor_type"]),
        "base_audit_mutations_actor_id_index" => index(["actor_id"]),
        "base_audit_mutations_auditable_type_index" => index(["auditable_type"]),
        "base_audit_mutations_auditable_id_index" => index(["auditable_id"]),
        "base_audit_mutations_source_index" => index(["source"]),
        "base_audit_mutations_event_index" => index(["event"]),
        "base_audit_mutations_trace_id_index" => index(["trace_id"]),
        "base_audit_mutations_occurred_at_index" => index(["occurred_at"]),
        "base_audit_mutations_auditable_occurred_index" =>
          index(["auditable_type", "auditable_id", "occurred_at"]),
        "base_audit_mutations_actor_type_actor_id_occurred_at_index" =>
          index(["actor_type", "actor_id", "occurred_at"]),
        "base_audit_mutations_subject_idx" =>
          index(
            ["subject_name", "subject_id", "subject_identifier", "occurred_at"],
            false,
            "subject_nameisnotnull"
          )
      },
      optional_columns: %{"impersonator_id" => column(:bigint)},
      optional_indexes: %{
        "base_audit_mutations_impersonator_id_index" =>
          index(["impersonator_id"], false, "impersonator_idisnotnull")
      },
      optional_groups: [impersonation_group("base_audit_mutations")],
      foreign_keys: %{}
    }
  end

  defp actions do
    %{
      name: "base_audit_actions",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_audit_actions_id_seq"}),
        "company_id" => column(:bigint),
        "tenant_id" => column(:bigint),
        "actor_type" => column({:varchar, 40}, false),
        "actor_id" => column(:bigint, false),
        "actor_role" => column({:varchar, 100}),
        "ip_address" => column(:inet),
        "url" => column(:text),
        "user_agent" => column({:varchar, 80}),
        "event" => column({:varchar, 255}, false),
        "payload" => column(:jsonb),
        "trace_id" => column({:varchar, 12}),
        "is_retained" => column(:boolean, false, {:boolean, false}),
        "occurred_at" => column({:timestamp, 0}, false)
      },
      indexes: %{
        "base_audit_actions_pkey" => index(["id"], true),
        "base_audit_actions_company_id_index" => index(["company_id"]),
        "base_audit_actions_tenant_id_index" => index(["tenant_id"]),
        "base_audit_actions_actor_type_index" => index(["actor_type"]),
        "base_audit_actions_actor_id_index" => index(["actor_id"]),
        "base_audit_actions_event_index" => index(["event"]),
        "base_audit_actions_trace_id_index" => index(["trace_id"]),
        "base_audit_actions_occurred_at_index" => index(["occurred_at"]),
        "base_audit_actions_event_occurred_at_index" => index(["event", "occurred_at"]),
        "base_audit_actions_actor_type_actor_id_occurred_at_index" =>
          index(["actor_type", "actor_id", "occurred_at"])
      },
      optional_columns: %{"impersonator_id" => column(:bigint)},
      optional_indexes: %{
        "base_audit_actions_impersonator_id_index" =>
          index(["impersonator_id"], false, "impersonator_idisnotnull")
      },
      optional_groups: [impersonation_group("base_audit_actions")],
      foreign_keys: %{}
    }
  end

  defp impersonation_group(table) do
    %{
      name: "base/audit impersonation operator",
      columns: ["impersonator_id"],
      indexes: ["#{table}_impersonator_id_index"]
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false, where \\ nil) do
    %{columns: columns, unique: unique, where: where}
  end
end
