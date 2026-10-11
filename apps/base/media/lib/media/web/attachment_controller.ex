defmodule Bilimbi.Base.Media.Web.AttachmentController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]
  alias Bilimbi.Base.Media
  alias Bilimbi.Base.Media.Web.Response

  def show(conn, %{"public_id" => id}) do
    case Media.download_attachment(conn.assigns.current_scope.scope, id) do
      {:ok, file} ->
        Response.send(conn, file, true)

      {:error, reason} when reason in [:not_found, :storage_unavailable] ->
        send_resp(conn, 404, "Not found")

      {:error, _} ->
        send_resp(conn, 403, "Forbidden")
    end
  end
end
