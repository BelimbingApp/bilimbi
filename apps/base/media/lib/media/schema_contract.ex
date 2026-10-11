defmodule Bilimbi.Base.Media.SchemaContract do
  @moduledoc "Compatible Belimbing asset metadata and tenant-owned private attachment bindings."
  @behaviour Bilimbi.Base.Database.SchemaContract

  @impl true
  def tables do
    [
      %{
        name: "base_media_assets",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "base_media_assets_id_seq"}),
          "parent_id" => column(:bigint),
          "disk" => column({:varchar, 255}, false),
          "storage_key" => column({:varchar, 255}, false),
          "original_filename" => column({:varchar, 255}),
          "mime_type" => column({:varchar, 255}),
          "file_size" => column(:bigint),
          "kind" => column({:varchar, 255}, false),
          "metadata" => column(:json),
          "created_at" => column({:timestamp, 0}),
          "updated_at" => column({:timestamp, 0})
        },
        indexes: %{
          "base_media_assets_pkey" => index(["id"], true),
          "base_media_assets_kind_index" => index(["kind"]),
          "base_media_assets_parent_id_kind_index" => index(["parent_id", "kind"]),
          "base_media_assets_disk_storage_key_index" => index(["disk", "storage_key"])
        },
        foreign_keys: %{
          "base_media_assets_parent_id_foreign" =>
            foreign_key("parent_id", "base_media_assets", :cascade)
        },
        checks: %{}
      },
      %{
        name: "base_media_attachments",
        columns: %{
          "id" => column(:bigint, false, {:sequence, "base_media_attachments_id_seq"}),
          "public_id" => column({:char, 26}, false),
          "tenant_id" => column(:bigint, false),
          "media_asset_id" => column(:bigint, false),
          "subject_type" => column({:varchar, 255}, false),
          "subject_id" => column({:varchar, 255}, false),
          "state" => column({:varchar, 255}, false),
          "uploaded_by_type" => column({:varchar, 255}, false),
          "uploaded_by_id" => column(:bigint, false),
          "submitted_at" => column({:timestamp, 0}),
          "retained_at" => column({:timestamp, 0}),
          "created_at" => column({:timestamp, 0}),
          "updated_at" => column({:timestamp, 0})
        },
        indexes: %{
          "base_media_attachments_pkey" => index(["id"], true),
          "base_media_attachments_public_id_unique" => index(["public_id"], true),
          "base_media_attachments_media_asset_id_unique" => index(["media_asset_id"], true),
          "base_media_attachments_state_index" => index(["state"]),
          "base_media_attachments_retained_at_index" => index(["retained_at"]),
          "media_attachments_tenant_subject_idx" =>
            index(["tenant_id", "subject_type", "subject_id"]),
          "media_attachments_draft_cleanup_idx" => index(["tenant_id", "state", "created_at"])
        },
        foreign_keys: %{
          "base_media_attachments_media_asset_id_foreign" =>
            foreign_key("media_asset_id", "base_media_assets", :restrict),
          "base_media_attachments_tenant_id_foreign" =>
            foreign_key("tenant_id", "tenants", :cascade)
        },
        checks: %{}
      }
    ]
  end

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp foreign_key(column, table, on_delete),
    do: %{
      columns: [column],
      references: {table, ["id"]},
      on_delete: on_delete,
      on_update: :nothing
    }
end
