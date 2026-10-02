defmodule BilimbiWeb.WebhookParsers do
  @moduledoc """
  Leaves the reserved webhook namespace unread. Its controller reads bounded
  raw bytes before any decoding, for every content type. All other requests
  retain the endpoint's normal parsers and browser CSRF behavior.
  """
  @behaviour Plug
  def init(opts), do: Plug.Parsers.init(opts)
  def call(%Plug.Conn{path_info: ["webhooks" | _]} = conn, _opts), do: conn
  def call(conn, opts), do: Plug.Parsers.call(conn, opts)
end
