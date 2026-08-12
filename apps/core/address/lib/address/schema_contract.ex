defmodule Bilimbi.Core.Address.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Core Address compatibility baseline.

  The Geonames foreign keys are a deferred all-or-nothing contribution. Their
  columns and indexes remain owned by Address and are always present.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_812_041_935

  def migration_version, do: @migration_version

  @impl true
  def tables, do: [addresses(), addressables()]

  defp addresses do
    %{
      name: "addresses",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "addresses_id_seq"}),
        "label" => column({:varchar, 255}),
        "phone" => column({:varchar, 255}),
        "line1" => column(:text),
        "line2" => column(:text),
        "line3" => column(:text),
        "locality" => column({:varchar, 255}),
        "postcode" => column({:varchar, 255}),
        "country_iso" => column({:varchar, 2}),
        "admin1Code" => column({:varchar, 20}),
        "rawInput" => column(:text),
        "source" => column({:varchar, 255}),
        "sourceRef" => column({:varchar, 255}),
        "parserVersion" => column({:varchar, 255}),
        "parseConfidence" => column({:numeric, 5, 4}),
        "parsed_at" => column({:timestamp, 0}),
        "normalized_at" => column({:timestamp, 0}),
        "normalization_notes" => column(:json),
        "verificationStatus" => column({:varchar, 255}, false, {:string, "unverified"}),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0}),
        "deleted_at" => column({:timestamp, 0}),
        "tenant_id" => column(:bigint, false)
      },
      indexes: %{
        "addresses_pkey" => index(["id"], true),
        "addresses_country_iso_index" => index(["country_iso"]),
        "addresses_admin1code_index" => index(["admin1Code"]),
        "addresses_source_index" => index(["source"]),
        "addresses_verificationstatus_index" => index(["verificationStatus"]),
        "addresses_tenant_index" => index(["tenant_id"])
      },
      foreign_keys: %{
        "addresses_tenant_foreign" => foreign_key("tenant_id", "tenants", "id", :restrict)
      },
      optional_foreign_keys: %{
        "addresses_country_iso_foreign" =>
          foreign_key("country_iso", "geonames_countries", "iso", :nilify_all),
        "addresses_admin1code_foreign" =>
          foreign_key("admin1Code", "geonames_admin1", "code", :nilify_all)
      },
      optional_groups: [
        %{
          name: "core/geonames address normalization",
          columns: [],
          indexes: [],
          foreign_keys: ["addresses_country_iso_foreign", "addresses_admin1code_foreign"]
        }
      ]
    }
  end

  defp addressables do
    %{
      name: "addressables",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "addressables_id_seq"}),
        "address_id" => column(:bigint, false),
        "addressable_type" => column({:varchar, 255}, false),
        "addressable_id" => column(:bigint, false),
        "kind" => column(:json, false, {:json, "[]"}),
        "is_primary" => column(:boolean, false, {:boolean, false}),
        "priority" => column(:smallint, false, {:integer, 0}),
        "valid_from" => column(:date),
        "valid_to" => column(:date),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "addressables_pkey" => index(["id"], true),
        "addressables_addressable_type_addressable_id_index" =>
          index(["addressable_type", "addressable_id"]),
        "addressables_is_primary_index" => index(["is_primary"])
      },
      foreign_keys: %{
        "addressables_address_id_foreign" =>
          foreign_key("address_id", "addresses", "id", :cascade)
      }
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp foreign_key(column, table, target_column, on_delete) do
    %{
      columns: [column],
      references: {table, [target_column]},
      on_delete: on_delete
    }
  end
end
