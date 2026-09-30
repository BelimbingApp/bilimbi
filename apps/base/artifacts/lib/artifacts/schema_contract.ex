defmodule Bilimbi.Base.Artifacts.SchemaContract do
  @moduledoc """
  Bilimbi-only private document metadata and lifecycle contract.

  The incoming Belimbing baseline has no artifact table, so baseline verification
  permits its absence. Once present, every column, index, check and foreign key
  must match the complete owned structure. As with existing optional Bilimbi-only
  contributions, an entirely absent contribution is valid before migration;
  a partially installed or altered contribution is never accepted.
  """
  @behaviour Bilimbi.Base.Database.SchemaContract

  @impl true
  def tables, do: []

  @impl true
  def verify_invariants(repo, opts) do
    schema = Keyword.get(opts, :prefix, "public")
    prefix = Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(schema)
    relation = prefix <> ".base_artifacts"

    case Ecto.Adapters.SQL.query!(repo, "SELECT to_regclass($1)::text", [relation]).rows do
      [[nil]] -> :ok
      [[_name]] -> Bilimbi.Base.Database.SchemaVerifier.verify(repo, artifact_tables(), opts)
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
          "expires_at" => column({:timestamp, 6}, false),
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
          "base_artifacts_bytes_positive" => %{expression: "byte_size > 0", validated: true}
        }
      }
    ]
  end

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}
end
