defmodule BilimbiWeb.WebhookChunkAdapter do
  @moduledoc false
  def read_req_body(state, opts),
    do: Plug.Adapters.Test.Conn.read_req_body(state, Keyword.put(opts, :length, 2))

  defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
end
