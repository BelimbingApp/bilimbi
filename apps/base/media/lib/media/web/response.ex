defmodule Bilimbi.Base.Media.Web.Response do
  @moduledoc false
  import Plug.Conn
  @inline_types ~w(image/jpeg image/png image/gif image/webp)

  # An encoded RFC 5987 filename cannot inject headers. Only raster types may
  # render inline; private attachments and all other asset types are downloads.
  def send(conn, file, private?) do
    mime = String.downcase(String.trim(Map.get(file, :mime_type) || ""))
    inline? = not private? and mime in @inline_types
    disposition = if inline?, do: "inline", else: "attachment"
    filename = URI.encode(file.filename, &URI.char_unreserved?/1)

    conn
    |> put_resp_content_type(if(inline?, do: mime, else: "application/octet-stream"), nil)
    |> put_resp_header("content-disposition", "#{disposition}; filename*=UTF-8''#{filename}")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(200, file.bytes)
  end
end
