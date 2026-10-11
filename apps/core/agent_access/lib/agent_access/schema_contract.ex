defmodule Bilimbi.Core.AgentAccess.SchemaContract do
  @moduledoc "Bilimbi-only OAuth storage. It contributes no Belimbing baseline; storage_tables/0 pins the new relations for verification and fixtures."
  @behaviour Bilimbi.Base.Database.SchemaContract
  def tables, do: []

  def storage_tables do
    [
      %{
        name: "core_agent_connections",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "core_agent_connections_id_seq"}),
          "tenant_id" => column(:bigint, false, nil),
          "company_id" => column(:bigint, false, nil),
          "user_id" => column(:bigint, false, nil),
          "agent_id" => column({:varchar, 255}, false, nil),
          "seen_agent_ids" => column(:jsonb, false, {:string, "{}"}),
          "expires_at" => column({:timestamp, 0}, false, nil),
          "revoked_at" => column({:timestamp, 0}, true, nil),
          "inserted_at" => column({:timestamp, 0}, false, nil),
          "updated_at" => column({:timestamp, 0}, false, nil)
        },
        indexes: %{
          "core_agent_connections_pkey" => index(["id"], true),
          "core_agent_connections_tenant_id_user_id_index" =>
            index(["tenant_id", "user_id"], false)
        },
        foreign_keys: %{
          "core_agent_connections_tenant_id_fkey" => %{
            columns: ["tenant_id"],
            references: {"tenants", ["id"]},
            on_delete: :restrict
          },
          "core_agent_connections_company_id_fkey" => %{
            columns: ["company_id"],
            references: {"companies", ["id"]},
            on_delete: :restrict
          },
          "core_agent_connections_user_id_fkey" => %{
            columns: ["user_id"],
            references: {"users", ["id"]},
            on_delete: :cascade
          }
        }
      },
      %{
        name: "core_agent_devices",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "core_agent_devices_id_seq"}),
          "device_hash" => column(:bytea, false, nil),
          "user_hash" => column(:bytea, false, nil),
          "client_id" => column({:varchar, 255}, false, nil),
          "agent_id" => column({:varchar, 255}, false, nil),
          "expires_at" => column({:timestamp, 0}, false, nil),
          "next_poll_at" => column({:timestamp, 0}, false, nil),
          "interval" => column(:integer, false, nil),
          "status" => column({:varchar, 255}, false, nil),
          "connection_id" => column(:bigint, true, nil),
          "inserted_at" => column({:timestamp, 0}, false, nil),
          "updated_at" => column({:timestamp, 0}, false, nil)
        },
        indexes: %{
          "core_agent_devices_pkey" => index(["id"], true),
          "core_agent_devices_device_hash_index" => index(["device_hash"], true),
          "core_agent_devices_user_hash_index" => index(["user_hash"], true)
        },
        foreign_keys: %{
          "core_agent_devices_connection_id_fkey" => %{
            columns: ["connection_id"],
            references: {"core_agent_connections", ["id"]},
            on_delete: :nilify_all
          }
        }
      },
      %{
        name: "core_agent_tokens",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "core_agent_tokens_id_seq"}),
          "connection_id" => column(:bigint, false, nil),
          "token_hash" => column(:bytea, false, nil),
          "kind" => column({:varchar, 255}, false, nil),
          "expires_at" => column({:timestamp, 0}, false, nil),
          "used_at" => column({:timestamp, 0}, true, nil),
          "inserted_at" => column({:timestamp, 0}, false, nil),
          "updated_at" => column({:timestamp, 0}, false, nil)
        },
        indexes: %{
          "core_agent_tokens_pkey" => index(["id"], true),
          "core_agent_tokens_token_hash_index" => index(["token_hash"], true)
        },
        foreign_keys: %{
          "core_agent_tokens_connection_id_fkey" => %{
            columns: ["connection_id"],
            references: {"core_agent_connections", ["id"]},
            on_delete: :cascade
          }
        }
      }
    ]
  end

  defp column(type, nullable, default), do: %{type: type, nullable: nullable, default: default}
  defp index(columns, unique), do: %{columns: columns, unique: unique, where: nil}
end
