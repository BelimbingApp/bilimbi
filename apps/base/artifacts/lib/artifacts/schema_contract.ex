defmodule Bilimbi.Base.Artifacts.SchemaContract do
  @moduledoc """
  Bilimbi-only private document metadata and lifecycle contract.

  The incoming Belimbing baseline has no artifact table, so baseline verification
  permits its absence. Once present, every column, index, check and foreign key
  must match the complete owned structure, and the retention guard triggers must
  be installed and enabled. As with existing optional Bilimbi-only
  contributions, an entirely absent contribution is valid before migration;
  a partially installed or altered contribution is never accepted.
  """
  @behaviour Bilimbi.Base.Database.SchemaContract

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  # Every user trigger the owned tables carry, as {table, trigger}. The guard
  # functions are the database side of the retention contract in
  # `Bilimbi.Base.Artifacts`; a disabled or missing trigger is drift.
  @triggers [
    ["base_artifact_retention_events", "base_artifact_retention_events_append_only"],
    ["base_artifact_retention_events", "base_artifact_retention_events_no_truncate"],
    ["base_artifacts", "base_artifacts_retention_guard"]
  ]

  @impl true
  def tables, do: []

  @impl true
  def verify_invariants(repo, opts) do
    schema = Keyword.get(opts, :prefix, "public")
    prefix = SchemaVerifier.quote_identifier!(schema)
    relation = prefix <> ".base_artifacts"

    case SQL.query!(repo, "SELECT to_regclass($1)::text", [relation]).rows do
      [[nil]] ->
        :ok

      [[_name]] ->
        with :ok <- SchemaVerifier.verify(repo, artifact_tables(), opts) do
          trigger_errors(repo, schema)
        end
    end
  end

  defp trigger_errors(repo, schema) do
    installed =
      SQL.query!(
        repo,
        """
        SELECT t.relname::text, g.tgname::text
        FROM pg_trigger g
        JOIN pg_class t ON t.oid = g.tgrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = $1 AND NOT g.tgisinternal AND g.tgenabled <> 'D'
          AND t.relname IN ('base_artifacts', 'base_artifact_retention_events')
        ORDER BY 1, 2
        """,
        [schema]
      ).rows

    if installed == @triggers do
      :ok
    else
      {:error,
       [
         "base_artifacts: retention guard triggers differ: " <>
           "expected #{inspect(@triggers)}, found #{inspect(installed)}"
       ]}
    end
  end

  @doc false
  def artifact_tables do
    [
      %{
        name: "base_artifacts",
        columns: %{
          "id" => column(:uuid, false),
          "tenant_id" => column(:bigint, false),
          "company_id" => column(:bigint, false),
          "owner_id" => column({:varchar, 255}, false),
          "owner_adapter" => column({:varchar, 255}, false),
          "subject" => column({:varchar, 255}, false),
          "kind" => column({:varchar, 255}, false),
          "content_type" => column({:varchar, 255}, false),
          "byte_size" => column(:bigint, false),
          "sha256" => column({:varchar, 64}, false),
          "storage_root" => column(:text, false),
          "expires_at" => column({:timestamp, 6}),
          "retain_until" => column({:timestamp, 6}),
          "legal_hold_at" => column({:timestamp, 6}),
          "ready_at" => column({:timestamp, 6}),
          "deleted_at" => column({:timestamp, 6}),
          "purged_at" => column({:timestamp, 6}),
          "purge_attempts" => column(:integer, false, {:integer, 0}),
          "purge_last_error" => column({:varchar, 255}),
          "purge_attempted_at" => column({:timestamp, 6}),
          "purge_held_at" => column({:timestamp, 6}),
          "inserted_at" => column({:timestamp, 6}, false),
          "updated_at" => column({:timestamp, 6}, false)
        },
        indexes: %{
          "base_artifacts_pkey" => index(["id"], true),
          "base_artifacts_retention_index" =>
            index(["tenant_id", "company_id", "owner_id", "expires_at"])
        },
        foreign_keys: %{
          "base_artifacts_tenant_id_fkey" => %{
            columns: ["tenant_id"],
            references: {"tenants", ["id"]},
            on_delete: :restrict,
            on_update: :nothing
          }
        },
        checks: %{
          "base_artifacts_company_positive" => %{expression: "company_id > 0", validated: true},
          "base_artifacts_bytes_positive" => %{expression: "byte_size > 0", validated: true},
          "base_artifacts_retention_exclusive" => %{
            expression: "(retain_until IS NULL) <> (expires_at IS NULL)",
            validated: true
          },
          "base_artifacts_hold_requires_retention" => %{
            expression: "legal_hold_at IS NULL OR retain_until IS NOT NULL",
            validated: true
          }
        }
      },
      %{
        name: "base_artifact_retention_events",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "base_artifact_retention_events_id_seq"}),
          "artifact_id" => column(:uuid, false),
          "tenant_id" => column(:bigint, false),
          "company_id" => column(:bigint, false),
          "owner_id" => column({:varchar, 255}, false),
          "event" => column({:varchar, 40}, false),
          "retain_until" => column({:timestamp, 6}, false),
          "legal_hold" => column(:boolean, false),
          "reason" => column({:varchar, 255}),
          "actor_type" => column({:varchar, 40}, false),
          "actor_id" => column(:bigint, false),
          "impersonator_id" => column(:bigint),
          "system_principal" => column({:varchar, 100}),
          "recorded_at" => column({:timestamp, 6}, false)
        },
        indexes: %{
          "base_artifact_retention_events_pkey" => index(["id"], true),
          "base_artifact_retention_events_artifact_index" => index(["artifact_id", "id"])
        },
        foreign_keys: %{
          "base_artifact_retention_events_artifact_id_fkey" => %{
            columns: ["artifact_id"],
            references: {"base_artifacts", ["id"]},
            on_delete: :restrict,
            on_update: :nothing
          },
          "base_artifact_retention_events_tenant_id_fkey" => %{
            columns: ["tenant_id"],
            references: {"tenants", ["id"]},
            on_delete: :restrict,
            on_update: :nothing
          }
        },
        checks: %{
          "base_artifact_retention_events_company_positive" => %{
            expression: "company_id > 0",
            validated: true
          },
          "base_artifact_retention_events_event_check" => %{
            expression:
              "event::text = ANY (ARRAY['retained'::character varying, " <>
                "'retention_extended'::character varying, 'hold_placed'::character varying, " <>
                "'hold_released'::character varying]::text[])",
            validated: true
          }
        }
      }
    ]
  end

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}
end
