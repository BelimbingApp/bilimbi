defmodule Bilimbi.Base.Settings.SchemaContract do
  @moduledoc "Pinned PostgreSQL contract for Base Settings."

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_813_113_500

  def migration_version, do: @migration_version

  @impl true
  def tables do
    [
      %{
        name: "base_settings",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "base_settings_id_seq"}),
          "key" => column({:varchar, 255}, false),
          "value" => column(:json, false),
          "is_encrypted" => column(:boolean, false, {:boolean, false}),
          "scope_type" => column({:varchar, 50}),
          "scope_id" => column(:bigint),
          "created_at" => column({:timestamp, 0}),
          "updated_at" => column({:timestamp, 0})
        },
        indexes: %{
          "base_settings_pkey" => index(["id"], true),
          "base_settings_key_scope_unique" => index(["key", "scope_type", "scope_id"], true),
          "base_settings_scope_type_scope_id_index" => index(["scope_type", "scope_id"]),
          "base_settings_global_key_unique" =>
            index(["key"], true, "scope_typeisnullandscope_idisnull")
        },
        foreign_keys: %{}
      }
    ]
  end

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false, where \\ nil),
    do: %{columns: columns, unique: unique, where: where}
end
