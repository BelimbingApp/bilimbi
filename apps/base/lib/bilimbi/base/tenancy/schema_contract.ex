defmodule Bilimbi.Base.Tenancy.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Base Tenancy compatibility baseline.
  """

  @migration_version 20_260_811_093_951

  def migration_version, do: @migration_version

  def tables do
    [
      %{
        name: "tenants",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "tenants_id_seq"}),
          "parent_id" => column(:bigint),
          "name" => column({:varchar, 255}, false),
          "status" => column({:varchar, 255}, false, {:string, "active"}),
          "is_platform_operator" => column(:boolean, false, {:boolean, false}),
          "created_at" => column({:timestamp, 0}),
          "updated_at" => column({:timestamp, 0}),
          "deleted_at" => column({:timestamp, 0})
        },
        indexes: %{
          "tenants_pkey" => index(["id"], true),
          "tenants_parent_id_index" => index(["parent_id"]),
          "tenants_status_index" => index(["status"]),
          "tenants_parent_id_status_index" => index(["parent_id", "status"]),
          "tenants_one_platform_operator" =>
            index(["is_platform_operator"], true, "is_platform_operator=true")
        },
        foreign_keys: %{}
      }
    ]
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false, where \\ nil) do
    %{columns: columns, unique: unique, where: where}
  end
end
