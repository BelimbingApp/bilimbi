defmodule Bilimbi.Core.Company.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Core Company compatibility baseline.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  @migration_version 20_260_811_093_956

  def migration_version, do: @migration_version

  @impl true
  def tables do
    [
      companies(),
      tenant_primary_companies(),
      relationship_types(),
      relationships(),
      external_accesses()
    ] ++
      [legal_entity_types(), department_types(), departments()]
  end

  @impl true
  def contributions do
    [
      %{
        name: "base_authz_roles",
        foreign_keys: %{
          "base_authz_roles_company_foreign" => foreign_key("company_id", "companies", :restrict)
        },
        checks: %{
          "base_authz_roles_custom_company_check" => %{
            expression: "is_system = (company_id IS NULL)",
            validated: true
          }
        }
      }
    ]
  end

  @impl true
  def verify_invariants(repo, opts) do
    schema = Keyword.get(opts, :prefix, "public")
    prefix = SchemaVerifier.quote_identifier!(schema)

    errors =
      SQL.query!(
        repo,
        """
        SELECT assignment.tenant_id,
               assignment.company_id,
               tenant.id,
               tenant.deleted_at,
               company.id,
               company.tenant_id,
               company.deleted_at
        FROM #{prefix}.tenant_primary_companies AS assignment
        LEFT JOIN #{prefix}.tenants AS tenant
          ON tenant.id = assignment.tenant_id
        LEFT JOIN #{prefix}.companies AS company
          ON company.id = assignment.company_id
         AND company.tenant_id = assignment.tenant_id
        ORDER BY assignment.tenant_id
        """,
        []
      ).rows
      |> Enum.flat_map(&assignment_errors/1)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp assignment_errors([
         tenant_id,
         _company_id,
         nil,
         _tenant_deleted_at,
         _id,
         _owner,
         _deleted
       ]) do
    ["tenant_primary_companies: assignment for missing tenant #{tenant_id}"]
  end

  defp assignment_errors([tenant_id, _company_id, _id, deleted_at, _company, _owner, _deleted])
       when not is_nil(deleted_at) do
    ["tenant_primary_companies: assignment belongs to soft-deleted tenant #{tenant_id}"]
  end

  defp assignment_errors([tenant_id, company_id, _id, _deleted, nil, _owner, _company_deleted]) do
    [
      "tenant_primary_companies: company #{company_id} is missing or does not belong to tenant #{tenant_id}"
    ]
  end

  defp assignment_errors([
         tenant_id,
         _company_id,
         _id,
         _tenant_deleted,
         _company,
         owner,
         nil
       ])
       when tenant_id == owner do
    []
  end

  defp assignment_errors([tenant_id, company_id, _id, _tenant_deleted, _company, owner, nil]) do
    [
      "tenant_primary_companies: company #{company_id} belongs to tenant #{owner}, expected #{tenant_id}"
    ]
  end

  defp assignment_errors([
         tenant_id,
         company_id,
         _id,
         _tenant_deleted,
         _company,
         _owner,
         _deleted
       ]) do
    ["tenant_primary_companies: company #{company_id} for tenant #{tenant_id} is soft-deleted"]
  end

  defp companies do
    %{
      name: "companies",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "companies_id_seq"}),
        "parent_id" => column(:bigint),
        "name" => column({:varchar, 255}, false),
        "code" => column({:varchar, 255}, false),
        "status" => column({:varchar, 255}, false, {:string, "active"}),
        "legal_name" => column({:varchar, 255}),
        "registration_number" => column({:varchar, 255}),
        "tax_id" => column({:varchar, 255}),
        "legal_entity_type_id" => column(:bigint),
        "jurisdiction" => column({:varchar, 255}),
        "email" => column({:varchar, 255}),
        "website" => column({:varchar, 255}),
        "scope_activities" => column(:json),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0}),
        "deleted_at" => column({:timestamp, 0}),
        "tenant_id" => column(:bigint, false)
      },
      indexes: %{
        "companies_pkey" => index(["id"], true),
        "companies_parent_id_index" => index(["parent_id"]),
        "companies_code_unique" => index(["code"], true),
        "companies_status_index" => index(["status"]),
        "companies_legal_entity_type_id_index" => index(["legal_entity_type_id"]),
        "companies_parent_id_status_index" => index(["parent_id", "status"]),
        "companies_created_at_index" => index(["created_at"]),
        "companies_tenant_id_index" => index(["tenant_id"]),
        "companies_id_tenant_unique" => index(["id", "tenant_id"], true)
      },
      foreign_keys: %{
        "companies_tenant_foreign" => foreign_key("tenant_id", "tenants", :restrict),
        "companies_parent_tenant_foreign" =>
          foreign_key(["parent_id", "tenant_id"], "companies", ["id", "tenant_id"], :restrict)
      }
    }
  end

  defp tenant_primary_companies do
    %{
      name: "tenant_primary_companies",
      columns: %{
        "tenant_id" => column(:bigint, false),
        "company_id" => column(:bigint, false)
      },
      indexes: %{
        "tenant_primary_companies_pkey" => index(["tenant_id"], true),
        "tenant_primary_companies_company_id_unique" => index(["company_id"], true)
      },
      foreign_keys: %{
        "tenant_primary_companies_tenant_foreign" =>
          foreign_key("tenant_id", "tenants", :restrict),
        "tenant_primary_companies_company_tenant_foreign" =>
          foreign_key(["company_id", "tenant_id"], "companies", ["id", "tenant_id"], :restrict)
      }
    }
  end

  defp relationship_types do
    %{
      name: "company_relationship_types",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "company_relationship_types_id_seq"}),
        "code" => column({:varchar, 255}, false),
        "name" => column({:varchar, 255}, false),
        "description" => column(:text),
        "is_external" => column(:boolean, false, {:boolean, false}),
        "is_active" => column(:boolean, false, {:boolean, true}),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "company_relationship_types_pkey" => index(["id"], true),
        "company_relationship_types_code_unique" => index(["code"], true),
        "company_relationship_types_is_active_code_index" => index(["is_active", "code"])
      },
      foreign_keys: %{}
    }
  end

  defp relationships do
    %{
      name: "company_relationships",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "company_relationships_id_seq"}),
        "company_id" => column(:bigint, false),
        "related_company_id" => column(:bigint, false),
        "relationship_type_id" => column(:bigint, false),
        "effective_from" => column(:date),
        "effective_to" => column(:date),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0}),
        "deleted_at" => column({:timestamp, 0})
      },
      indexes: %{
        "company_relationships_pkey" => index(["id"], true),
        "company_relationships_company_id_relationship_type_id_index" =>
          index(["company_id", "relationship_type_id"]),
        "company_relationships_related_type_index" =>
          index(["related_company_id", "relationship_type_id"]),
        "company_relationships_effective_from_effective_to_index" =>
          index(["effective_from", "effective_to"]),
        "company_relationship_unique" =>
          index(
            ["company_id", "related_company_id", "relationship_type_id", "effective_from"],
            true
          )
      },
      foreign_keys: %{
        "company_relationships_company_id_foreign" => foreign_key("company_id", "companies"),
        "company_relationships_related_company_id_foreign" =>
          foreign_key("related_company_id", "companies"),
        "company_relationships_relationship_type_id_foreign" =>
          foreign_key("relationship_type_id", "company_relationship_types")
      }
    }
  end

  defp external_accesses do
    %{
      name: "company_external_accesses",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "company_external_accesses_id_seq"}),
        "company_id" => column(:bigint, false),
        "relationship_id" => column(:bigint, false),
        "permissions" => column(:json),
        "is_active" => column(:boolean, false, {:boolean, true}),
        "access_granted_at" => column({:timestamp, 0}),
        "access_expires_at" => column({:timestamp, 0}),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0}),
        "deleted_at" => column({:timestamp, 0})
      },
      indexes: %{
        "company_external_accesses_pkey" => index(["id"], true),
        "company_external_accesses_company_id_is_active_index" =>
          index(["company_id", "is_active"]),
        "company_external_accesses_access_expires_at_index" => index(["access_expires_at"])
      },
      optional_columns: %{
        "user_id" => column(:bigint)
      },
      optional_indexes: %{
        "company_external_accesses_user_id_is_active_index" => index(["user_id", "is_active"])
      },
      foreign_keys: %{
        "company_external_accesses_company_id_foreign" => foreign_key("company_id", "companies"),
        "company_external_accesses_relationship_id_foreign" =>
          foreign_key("relationship_id", "company_relationships")
      },
      optional_foreign_keys: %{
        "company_external_accesses_user_id_foreign" =>
          foreign_key("user_id", "users", :nilify_all)
      },
      optional_groups: [
        %{
          name: "core/user external-access owner",
          columns: ["user_id"],
          indexes: ["company_external_accesses_user_id_is_active_index"],
          foreign_keys: ["company_external_accesses_user_id_foreign"]
        }
      ]
    }
  end

  defp legal_entity_types do
    %{
      name: "company_legal_entity_types",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "company_legal_entity_types_id_seq"}),
        "code" => column({:varchar, 255}, false),
        "name" => column({:varchar, 255}, false),
        "description" => column(:text),
        "is_active" => column(:boolean, false, {:boolean, true}),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "company_legal_entity_types_pkey" => index(["id"], true),
        "company_legal_entity_types_code_unique" => index(["code"], true),
        "company_legal_entity_types_is_active_code_index" => index(["is_active", "code"])
      },
      foreign_keys: %{}
    }
  end

  defp department_types do
    %{
      name: "company_department_types",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "company_department_types_id_seq"}),
        "code" => column({:varchar, 255}, false),
        "name" => column({:varchar, 255}, false),
        "category" => column({:varchar, 255}, false),
        "description" => column(:text),
        "is_active" => column(:boolean, false, {:boolean, true}),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "company_department_types_pkey" => index(["id"], true),
        "company_department_types_code_unique" => index(["code"], true),
        "company_department_types_category_index" => index(["category"]),
        "company_department_types_is_active_category_index" => index(["is_active", "category"])
      },
      foreign_keys: %{}
    }
  end

  defp departments do
    %{
      name: "company_departments",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "company_departments_id_seq"}),
        "company_id" => column(:bigint, false),
        "department_type_id" => column(:bigint, false),
        "head_id" => column(:bigint),
        "status" => column({:varchar, 255}, false, {:string, "active"}),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "company_departments_pkey" => index(["id"], true),
        "company_departments_head_id_index" => index(["head_id"]),
        "company_departments_status_index" => index(["status"]),
        "company_departments_company_id_department_type_id_unique" =>
          index(["company_id", "department_type_id"], true)
      },
      foreign_keys: %{
        "company_departments_company_id_foreign" => foreign_key("company_id", "companies"),
        "company_departments_department_type_id_foreign" =>
          foreign_key("department_type_id", "company_department_types"),
        "company_departments_head_id_foreign" => foreign_key("head_id", "employees", :nilify_all)
      }
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp foreign_key(column, table, on_delete \\ :cascade) do
    foreign_key(List.wrap(column), table, ["id"], on_delete)
  end

  defp foreign_key(columns, table, target_columns, on_delete) do
    %{
      columns: List.wrap(columns),
      references: {table, List.wrap(target_columns)},
      on_delete: on_delete
    }
  end
end
