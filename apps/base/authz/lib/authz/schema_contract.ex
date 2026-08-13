defmodule Bilimbi.Base.Authz.SchemaContract do
  @moduledoc "Pinned PostgreSQL contract for the Base Authz compatibility baseline."

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_811_093_953

  def migration_version, do: @migration_version

  @impl true
  def tables do
    [roles(), role_capabilities(), principal_roles(), principal_capabilities(), decision_logs()]
  end

  defp roles do
    %{
      name: "base_authz_roles",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_authz_roles_id_seq"}),
        "company_id" => column(:bigint),
        "name" => column({:varchar, 255}, false),
        "code" => column({:varchar, 255}, false),
        "description" => column(:text),
        "is_system" => column(:boolean, false, {:boolean, false}),
        "grant_all" => column(:boolean, false, {:boolean, false}),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_authz_roles_pkey" => index(["id"], true),
        "base_authz_roles_company_id_index" => index(["company_id"]),
        "base_authz_roles_company_id_code_unique" => index(["company_id", "code"], true)
      },
      foreign_keys: %{},
      optional_foreign_keys: %{
        "base_authz_roles_company_foreign" => foreign_key("company_id", "companies", :restrict)
      },
      optional_checks: %{
        "base_authz_roles_custom_company_check" => check("is_system = (company_id IS NULL)")
      },
      optional_groups: [
        %{
          name: "core/company role ownership",
          foreign_keys: ["base_authz_roles_company_foreign"],
          checks: ["base_authz_roles_custom_company_check"]
        }
      ]
    }
  end

  defp role_capabilities do
    %{
      name: "base_authz_role_capabilities",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_authz_role_capabilities_id_seq"}),
        "role_id" => column(:bigint, false),
        "capability_key" => column({:varchar, 255}, false),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_authz_role_capabilities_pkey" => index(["id"], true),
        "base_authz_role_capabilities_role_id_capability_key_unique" =>
          index(["role_id", "capability_key"], true),
        "base_authz_role_capabilities_capability_key_index" => index(["capability_key"])
      },
      foreign_keys: %{
        "base_authz_role_capabilities_role_id_foreign" =>
          foreign_key("role_id", "base_authz_roles")
      }
    }
  end

  defp principal_roles do
    %{
      name: "base_authz_principal_roles",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_authz_principal_roles_id_seq"}),
        "company_id" => column(:bigint),
        "principal_type" => column({:varchar, 40}, false),
        "principal_id" => column(:bigint, false),
        "role_id" => column(:bigint, false),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_authz_principal_roles_pkey" => index(["id"], true),
        "base_authz_principal_roles_company_id_index" => index(["company_id"]),
        "base_authz_principal_roles_principal_type_principal_id_index" =>
          index(["principal_type", "principal_id"]),
        "base_authz_principal_roles_unique" =>
          index(["company_id", "principal_type", "principal_id", "role_id"], true)
      },
      foreign_keys: %{
        "base_authz_principal_roles_role_id_foreign" => foreign_key("role_id", "base_authz_roles")
      }
    }
  end

  defp principal_capabilities do
    %{
      name: "base_authz_principal_capabilities",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_authz_principal_capabilities_id_seq"}),
        "company_id" => column(:bigint),
        "principal_type" => column({:varchar, 40}, false),
        "principal_id" => column(:bigint, false),
        "capability_key" => column({:varchar, 255}, false),
        "is_allowed" => column(:boolean, false, {:boolean, true}),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_authz_principal_capabilities_pkey" => index(["id"], true),
        "base_authz_principal_capabilities_company_id_index" => index(["company_id"]),
        "base_authz_principal_caps_principal_index" => index(["principal_type", "principal_id"]),
        "base_authz_principal_capabilities_capability_key_index" => index(["capability_key"]),
        "base_authz_principal_caps_unique" =>
          index(["company_id", "principal_type", "principal_id", "capability_key"], true)
      },
      foreign_keys: %{}
    }
  end

  defp decision_logs do
    %{
      name: "base_authz_decision_logs",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_authz_decision_logs_id_seq"}),
        "company_id" => column(:bigint),
        "actor_type" => column({:varchar, 40}, false),
        "actor_id" => column(:bigint, false),
        "acting_for_user_id" => column(:bigint),
        "capability" => column({:varchar, 255}, false),
        "resource_type" => column({:varchar, 255}),
        "resource_id" => column({:varchar, 255}),
        "allowed" => column(:boolean, false),
        "reason_code" => column({:varchar, 255}, false),
        "applied_policies" => column(:json),
        "context" => column(:json),
        "trace_id" => column({:varchar, 12}),
        "occurred_at" => column({:timestamp, 0}, false),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_authz_decision_logs_pkey" => index(["id"], true),
        "base_authz_decision_logs_company_id_index" => index(["company_id"]),
        "base_authz_decision_logs_actor_type_index" => index(["actor_type"]),
        "base_authz_decision_logs_actor_id_index" => index(["actor_id"]),
        "base_authz_decision_logs_acting_for_user_id_index" => index(["acting_for_user_id"]),
        "base_authz_decision_logs_capability_index" => index(["capability"]),
        "base_authz_decision_logs_resource_type_index" => index(["resource_type"]),
        "base_authz_decision_logs_resource_id_index" => index(["resource_id"]),
        "base_authz_decision_logs_allowed_index" => index(["allowed"]),
        "base_authz_decision_logs_reason_code_index" => index(["reason_code"]),
        "base_authz_decision_logs_trace_id_index" => index(["trace_id"]),
        "base_authz_decision_logs_occurred_at_index" => index(["occurred_at"]),
        "base_authz_decision_logs_actor_type_actor_id_occurred_at_index" =>
          index(["actor_type", "actor_id", "occurred_at"]),
        "base_authz_decision_logs_capability_allowed_index" => index(["capability", "allowed"])
      },
      foreign_keys: %{}
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp foreign_key(column, table, on_delete \\ :cascade) do
    %{
      columns: [column],
      references: {table, ["id"]},
      on_delete: on_delete
    }
  end

  defp check(expression), do: %{expression: expression, validated: true}
end
