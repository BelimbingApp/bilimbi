defmodule Bilimbi.Base.AgentApi.SchemaContract do
  @moduledoc "Bilimbi-only plan digests; no business values or credentials are stored."
  @behaviour Bilimbi.Base.Database.SchemaContract
  def tables, do: []

  def storage_tables do
    [
      %{
        name: "base_agent_api_plans",
        columns: %{
          "id" => column({:varchar, 64}, false),
          "tenant_id" => column(:bigint, false),
          "binding_hash" => column(:bytea, false),
          "operations_hash" => column(:bytea, false),
          "preview_hash" => column(:bytea, false),
          "expires_at" => column({:timestamp, 0}, false),
          "used_at" => column({:timestamp, 0}, true)
        },
        indexes: %{
          "base_agent_api_plans_pkey" => %{columns: ["id"], unique: true, where: nil},
          "base_agent_api_plans_expires_at_index" => %{
            columns: ["expires_at"],
            unique: false,
            where: nil
          }
        },
        foreign_keys: %{
          "base_agent_api_plans_tenant_id_fkey" => %{
            columns: ["tenant_id"],
            references: {"tenants", ["id"]},
            on_delete: :restrict
          }
        }
      }
    ]
  end

  defp column(type, nullable), do: %{type: type, nullable: nullable, default: nil}
end
