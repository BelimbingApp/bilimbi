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
      "pdf.node_binary" =>
        setting(
          :string,
          "node",
          "PDF Node.js executable",
          "Node.js 22 or newer for isolated PDF tool execution."
        ),
      "pdf.chromium.binary" =>
        setting(
          :string,
          "chromium",
          "PDF Chromium executable",
          "Sandboxed Chromium executable for HTML printing."
        ),
      "pdf.qpdf.binary" =>
        setting(
          :string,
          "qpdf",
          "PDF qpdf executable",
          "qpdf 10.6 or newer for AES-256 protection."
        ),
      "pdf.qpdf.timeout_seconds" =>
        setting(
          :integer,
          60,
          "PDF encryption timeout (seconds)",
          "Maximum runtime of one qpdf process.",
          minimum: 1,
          maximum: 600
        ),
      "pdf.render_timeout_seconds" =>
        setting(
          :integer,
          30,
          "PDF render timeout (seconds)",
          "Maximum runtime of one Chromium render.",
          minimum: 1,
          maximum: 600
        ),
      "pdf.render_origin" =>
        setting(
          :string,
          "",
          "PDF render origin",
          "Application origin reachable from Chromium; signed render requests must reach the issuing node.",
          validator:
            {Bilimbi.Base.Artifacts.PDF, :valid_origin_setting?,
             "must be empty or an HTTP(S) origin without a path"}
        ),
      "pdf.signed_url_ttl_seconds" =>
        setting(
          :integer,
          60,
          "PDF render token lifetime (seconds)",
          "Expiry of single-use signed render URLs.",
          minimum: 1,
          maximum: 600
        ),
      "pdf.max_render_tokens" =>
        setting(
          :integer,
          100,
          "Maximum pending PDF render tokens",
          "Maximum sensitive render requests held in memory on each node.",
          minimum: 1,
          maximum: 10_000
        ),
      "pdf.paper.format" =>
        setting(:string, "A4", "PDF paper format", "A4, A3, A5, Letter, Legal or Tabloid.",
          validator:
            {Bilimbi.Base.Artifacts.PDF.Engine, :valid_format?,
             "must be a supported paper format"}
        ),
      "pdf.paper.print_background" =>
        setting(
          :boolean,
          true,
          "Print PDF backgrounds",
          "Include template background graphics in HTML PDFs."
        ),
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
