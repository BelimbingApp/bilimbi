defmodule Bilimbi.Base.Audit.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Base Audit compatibility baseline.

  The `impersonator_id` column and its partial index on both tables are the
  Bilimbi-only impersonation contribution (migration `20260914090000`). They
  are declared as an optional group: an adopted Belimbing database verifies
  without them, a migrated Bilimbi database verifies with them, and a table
  carrying only half of the pair is drift.

  The `system_principal` column and its partial index are the Bilimbi-only
  system principal contribution (migration `20260927090000`, ADR 0017),
  declared the same way as a second optional group.

  The tenant timeline indexes on both tables are individually optional, not
  another group. Migration `20261003120000` adds `tenant_id`, then
  `occurred_at` and `id` descending. An adopted Belimbing database verifies
  without them. A present index must match those columns and that order.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_813_114_300

  def migration_version, do: @migration_version

  @impl true
  def tables,
    do: [mutations(), actions()] ++ Enum.map(evidence_tables(), &Map.put(&1, :optional, true))

  @impl true
  def verify_invariants(repo, opts) do
    prefix = Keyword.get(opts, :prefix, "public")
    sql = Ecto.Adapters.SQL
    # Optional Bilimbi-only evolution: the incoming Belimbing baseline has none.
    hardened? =
      sql.query!(
        repo,
        """
        SELECT EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_schema = $1 AND (
            (table_name IN ('base_audit_actions', 'base_audit_mutations') AND column_name = 'recorded_at')
            OR table_name IN ('base_audit_action_metadata', 'base_audit_capture_failures')))
        """,
        [prefix]
      ).rows == [[true]]

    if hardened? do
      present =
        sql.query!(
          repo,
          "SELECT table_name FROM information_schema.tables WHERE table_schema = $1",
          [prefix]
        ).rows
        |> List.flatten()

      errors =
        for %{name: name} <- evidence_tables(),
            name not in present,
            do: "missing table #{prefix}.#{name}"

      recording_errors =
        case sql.query!(
               repo,
               """
               SELECT count(*) FROM information_schema.columns
               WHERE table_schema = $1 AND table_name IN ('base_audit_actions', 'base_audit_mutations')
                 AND column_name = 'recorded_at'
               """,
               [prefix]
             ).rows do
          [[2]] -> []
          _ -> ["base/audit: incomplete database recording clocks"]
        end

      trigger_errors =
        for table <- ~w(base_audit_actions base_audit_mutations base_audit_capture_failures),
            {suffix, type} <- [{"evidence_guard", 31}, {"truncate_guard", 34}],
            sql.query!(
              repo,
              """
              SELECT EXISTS (SELECT 1 FROM pg_trigger t
                JOIN pg_class c ON c.oid = t.tgrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                JOIN pg_proc p ON p.oid = t.tgfoid
                WHERE n.nspname = $1 AND c.relname = $2 AND t.tgname = $3
                  AND t.tgtype = $4 AND t.tgenabled IN ('O', 'A')
                  AND p.proname = 'base_audit_evidence_v1')
              """,
              [prefix, table, "#{table}_#{suffix}", type]
            ).rows != [[true]],
            do: "#{table}: missing or disabled #{suffix}"

      case errors ++ recording_errors ++ trigger_errors do
        [] -> :ok
        errors -> {:error, errors}
      end
    else
      :ok
    end
  end

  defp evidence_tables do
    [
      %{
        name: "base_audit_action_metadata",
        columns: %{
          "action_id" => column(:bigint, false),
          "is_retained" => column(:boolean, false, {:boolean, false})
        },
        indexes: %{"base_audit_action_metadata_pkey" => index(["action_id"], true)},
        foreign_keys: %{
          "base_audit_action_metadata_action_id_fkey" => %{
            columns: ["action_id"],
            references: {"base_audit_actions", ["id"]},
            on_delete: :restrict
          }
        }
      },
      %{
        name: "base_audit_capture_failures",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "base_audit_capture_failures_id_seq"}),
          "action" => column(:text, false),
          "schema_name" => column(:text, false),
          "error_type" => column(:text, false),
          "trace_id" => column(:text),
          "actor_type" => column({:varchar, 40}, false),
          "actor_id" => column(:bigint, false),
          "company_id" => column(:bigint),
          "tenant_id" => column(:bigint),
          "impersonator_id" => column(:bigint),
          "system_principal" => column({:varchar, 100}),
          "recorded_at" => column({:timestamp, 6}, false)
        },
        indexes: %{"base_audit_capture_failures_pkey" => index(["id"], true)},
        foreign_keys: %{}
      }
    ]
  end

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
      optional_columns: %{
        "recorded_at" => column({:timestamp, 6}),
        "impersonator_id" => column(:bigint),
        "system_principal" => column({:varchar, 100})
      },
      optional_indexes: %{
        "base_audit_mutations_tenant_timeline_index" =>
          index(["tenant_id", "occurred_at", "id"], false, nil, [false, true, true]),
        "base_audit_mutations_impersonator_id_index" =>
          index(["impersonator_id"], false, "impersonator_idisnotnull"),
        "base_audit_mutations_system_principal_index" =>
          index(["system_principal"], false, "system_principalisnotnull")
      },
      optional_groups: [
        impersonation_group("base_audit_mutations"),
        system_principal_group("base_audit_mutations")
      ],
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
      optional_columns: %{
        "recorded_at" => column({:timestamp, 6}),
        "impersonator_id" => column(:bigint),
        "system_principal" => column({:varchar, 100})
      },
      optional_indexes: %{
        "base_audit_actions_tenant_timeline_index" =>
          index(["tenant_id", "occurred_at", "id"], false, nil, [false, true, true]),
        "base_audit_actions_impersonator_id_index" =>
          index(["impersonator_id"], false, "impersonator_idisnotnull"),
        "base_audit_actions_system_principal_index" =>
          index(["system_principal"], false, "system_principalisnotnull")
      },
      optional_groups: [
        impersonation_group("base_audit_actions"),
        system_principal_group("base_audit_actions")
      ],
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

  defp system_principal_group(table) do
    %{
      name: "base/audit system principal",
      columns: ["system_principal"],
      indexes: ["#{table}_system_principal_index"]
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false, where \\ nil, order \\ nil) do
    %{columns: columns, unique: unique, where: where, order: order}
  end
end
