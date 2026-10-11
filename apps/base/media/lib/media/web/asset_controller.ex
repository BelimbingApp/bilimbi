defmodule Bilimbi.Base.Media.Web.AssetController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]
  alias Bilimbi.Base.Media
  alias Bilimbi.Base.Media.Web.Response

  def show(conn, %{"id" => id} = params) do
    result =
      with {id, ""} when id > 0 <- Integer.parse(id),
           {:ok, file} <- Media.read_signed_asset(id, params["token"], conn.secret_key_base),
           do: {:ok, file}

    case result do
      {:ok, file} ->
        Response.send(conn, file, false)

      {:error, reason} when reason in [:invalid, :missing, :expired, :private_attachment] ->
        send_resp(conn, 403, "Forbidden")

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
