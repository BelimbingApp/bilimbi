defmodule Bilimbi.Core.AgentAccess.Web.PluginController do
  @moduledoc "Downloads the installation's non-secret plugin package for the signed-in person."
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn
  alias Bilimbi.Core.AgentAccess

  def download(conn, params) do
    # The host-configured origin is authoritative, including behind a proxy.
    endpoint = conn.private.phoenix_endpoint
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    case AgentAccess.plugin_download(
           conn.assigns.current_scope.scope,
           endpoint.url(),
           params["client_id"]
         ) do
      {:ok, bytes} ->
        send_download(conn, {:binary, bytes},
          filename: "bilimbi-chatgpt-plugin.zip",
          content_type: "application/zip"
        )

      {:error, :person_required} ->
        conn |> put_status(403) |> text("Use your own account to download the plugin.")

      {:error, :invalid_client} ->
        conn |> put_status(404) |> text("Choose a registered OAuth client on the plugin page.")

      {:error, :https_required} ->
        conn
        |> put_status(409)
        |> text("Ask your administrator to configure this installation's HTTPS address.")

      {:error, :package_unavailable} ->
        conn |> put_status(503) |> text("The plugin package is temporarily unavailable.")
    end
  end
end
