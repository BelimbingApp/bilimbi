defmodule Bilimbi.Base.Media.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      authz: %{capabilities: ["admin.system.media.manage"]},
      settings: %{
        definitions: %{
          "media.disks" =>
            setting(
              :array,
              %{},
              "Media storage disks",
              "JSON object of legacy disk names and existing absolute private directories. Roots must have permissions 0700 and remain stable while their assets exist."
            ),
          "media.attachment_disk" =>
            setting(
              :string,
              "local",
              "Private attachment disk",
              "Configured disk used for new attachments."
            ),
          "media.max_bytes" =>
            Map.put(
              setting(
                :integer,
                10_485_760,
                "Maximum upload bytes",
                "Maximum size of new media uploads and attachments."
              ),
              :minimum,
              1
            ),
          "media.attachment_allowed_types" =>
            setting(
              :array,
              [
                "application/pdf",
                "image/jpeg",
                "image/png",
                "image/gif",
                "image/webp",
                "text/plain",
                "text/csv",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
              ],
              "Attachment file types",
              "JSON array of allowed detected MIME types. Active markup is always refused."
            ),
          "media.stream_ttl_seconds" =>
            Map.put(
              setting(
                :integer,
                300,
                "Asset link lifetime",
                "Seconds a newly issued signed asset stream link remains valid."
              ),
              :minimum,
              1
            )
        },
        runtime_claims: []
      }
    }
  end

  defp setting(type, default, label, help),
    do: %{
      type: type,
      default: default,
      scopes: [:global],
      label: label,
      help: help,
      editable: "operator",
      capability: "admin.system.media.manage"
    }
end
