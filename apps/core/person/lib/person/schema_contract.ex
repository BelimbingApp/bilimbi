defmodule Bilimbi.Core.Person.SchemaContract do
  @moduledoc "Bilimbi-only person identity, affiliation and role structure, optional during baseline adoption."
  @behaviour Bilimbi.Base.Database.SchemaContract
  @impl true
  def tables do
    [
      %{
        name: "core_people",
        optional: true,
        columns:
          Map.merge(common("core_people"), %{
            "full_name" => column({:varchar, 255}, false),
            "email" => column({:varchar, 255}),
            "phone" => column({:varchar, 255}),
            "retired_at" => column({:timestamp, 0})
          }),
        indexes: %{
          "core_people_pkey" => index(["id"], true),
          "core_people_tenant_id_full_name_index" => index(["tenant_id", "full_name"]),
          "core_people_id_tenant_id_index" => index(["id", "tenant_id"], true)
        },
        foreign_keys: %{"core_people_tenant_id_fkey" => fk(["tenant_id"], "tenants", ["id"])}
      },
      %{
        name: "core_person_affiliations",
        optional: true,
        columns:
          Map.merge(common("core_person_affiliations"), %{
            "person_id" => column(:bigint, false),
            "company_id" => column(:bigint, false),
            "title" => column({:varchar, 255}),
            "email" => column({:varchar, 255}),
            "phone" => column({:varchar, 255}),
            "legacy_employee_id" => column(:bigint),
            "unlinked_at" => column({:timestamp, 0})
          }),
        indexes: %{
          "core_person_affiliations_pkey" => index(["id"], true),
          "core_person_affiliations_legacy_employee_id_index" =>
            index(["legacy_employee_id"], true),
          "core_person_affiliations_live_unique" => %{
            columns: ["person_id", "company_id"],
            unique: true,
            where: "unlinked_at IS NULL"
          },
          "core_person_affiliations_tenant_id_person_id_index" =>
            index(["tenant_id", "person_id"])
        },
        foreign_keys: %{
          "core_person_affiliations_tenant_id_fkey" => fk(["tenant_id"], "tenants", ["id"]),
          "core_person_affiliations_company_id_fkey" => fk(["company_id"], "companies", ["id"]),
          "core_person_affiliations_person_tenant_foreign" =>
            fk(["person_id", "tenant_id"], "core_people", ["id", "tenant_id"])
        }
      },
      %{
        name: "core_person_relationships",
        optional: true,
        columns:
          Map.merge(common("core_person_relationships"), %{
            "person_id" => column(:bigint, false),
            "company_id" => column(:bigint, false),
            "relationship_type_id" => column(:bigint, false),
            "effective_from" => column(:date),
            "effective_to" => column(:date),
            "deleted_at" => column({:timestamp, 0})
          }),
        indexes: %{
          "core_person_relationships_pkey" => index(["id"], true),
          "core_person_relationship_live_unique" => %{
            columns: ["company_id", "person_id", "relationship_type_id"],
            unique: true,
            where: "deleted_at IS NULL AND effective_to IS NULL"
          },
          "core_person_relationships_tenant_id_person_id_index" =>
            index(["tenant_id", "person_id"])
        },
        foreign_keys: %{
          "core_person_relationships_tenant_id_fkey" => fk(["tenant_id"], "tenants", ["id"]),
          "core_person_relationships_company_id_fkey" => fk(["company_id"], "companies", ["id"]),
          "core_person_relationships_relationship_type_id_fkey" =>
            fk(["relationship_type_id"], "company_relationship_types", ["id"]),
          "core_person_relationships_person_tenant_foreign" =>
            fk(["person_id", "tenant_id"], "core_people", ["id", "tenant_id"])
        }
      }
    ]
  end

  @impl true
  def verify_invariants(repo, opts) do
    prefix = Keyword.get(opts, :prefix, "public")
    names = Enum.map(tables(), & &1.name)

    [[count]] =
      Ecto.Adapters.SQL.query!(
        repo,
        "SELECT count(*) FROM information_schema.tables WHERE table_schema = $1 AND table_name = ANY($2)",
        [prefix, names]
      ).rows

    if count in [0, length(names)],
      do: :ok,
      else:
        {:error,
         ["core/person: identity, affiliation and role structure must be installed together"]}
  end

  defp common(table),
    do: %{
      "id" => column(:bigint, false, {:sequence, table <> "_id_seq"}),
      "tenant_id" => column(:bigint, false),
      "created_at" => column({:timestamp, 0}),
      "updated_at" => column({:timestamp, 0})
    }

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp fk(columns, table, references),
    do: %{columns: columns, references: {table, references}, on_delete: :restrict}
end
