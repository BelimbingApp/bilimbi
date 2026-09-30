defmodule Bilimbi.Base.Artifacts.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      settings: %{definitions: definitions(), runtime_claims: []},
      authz: %{capabilities: ["admin.system.artifacts.manage"]}
    }
  end

  defp definitions do
    %{
      "artifacts.storage_root" =>
        setting(
          :string,
          "",
          "Private document directory",
          "Existing absolute directory with permissions 0700, outside public/static/assets directories."
        ),
      "artifacts.retention_days" =>
        setting(
          :integer,
          nil,
          "Document retention days",
          "Required before storing documents. Applies to new documents; expiry is fixed when stored.",
          nullable: true,
          minimum: 1
        ),
      "artifacts.max_bytes" =>
        setting(
          :integer,
          10_485_760,
          "Maximum document bytes",
          "Maximum size of an uploaded or generated document.",
          minimum: 1
        ),
      "artifacts.purge_batch_size" =>
        setting(
          :integer,
          100,
          "Document purge batch size",
          "Maximum documents considered by each owner-scoped retention call.",
          minimum: 1
        ),
      "artifacts.purge_retry_minutes" =>
        setting(
          :integer,
          60,
          "Document purge retry interval (minutes)",
          "Minimum wait before retention retries a document whose purge failed or was refused.",
          minimum: 1
        ),
      "artifacts.purge_max_attempts" =>
        setting(
          :integer,
          5,
          "Document purge attempts before hold",
          "Failed or refused purges after which a document is held for an operator to retry or resolve.",
          minimum: 1
        )
    }
  end

  defp setting(type, default, label, help, extra \\ []) do
    Map.merge(
      %{
        type: type,
        scopes: [:global],
        default: default,
        label: label,
        help: help,
        editable: "operator",
        capability: "admin.system.artifacts.manage"
      },
      Map.new(extra)
    )
  end
end
