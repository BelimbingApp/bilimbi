defmodule BilimbiWeb.FramedRender do
  @moduledoc """
  Tells a page it is shown inside a workspace tile, so the shell renders it
  chromeless.

  Browsers send `Sec-Fetch-Dest: iframe` on a navigation inside a frame. The
  generated `live_session` blocks pass `session/1` as their session MFA, so
  that one fact enters the signed LiveView session of the HTTP request that
  mounted the page, and `on_mount/4` reads it back on the disconnected and
  the connected mount alike. Live navigation inside the frame stays within
  the same `live_session` and reuses that session, which is what keeps the
  flag after the frame's first page. The flag never touches the cookie
  session: every tab shares that, and a page in another tab is not framed.

  A browser that does not send the header renders a tile with the full
  shell inside it: ugly, but every page still works. The layout reads the
  flag from `current_scope[:framed]`, so there is nothing for a page to pass.
  """

  import Phoenix.Component, only: [assign: 3]

  @session_key "bilimbi_framed"

  @doc "Whether this request was made by a frame."
  @spec framed_request?(Plug.Conn.t()) :: boolean()
  def framed_request?(%Plug.Conn{} = conn) do
    Plug.Conn.get_req_header(conn, "sec-fetch-dest") in [["iframe"], ["frame"]]
  end

  @doc "The live session entry carrying the frame flag; the session MFA of every discovered `live_session`."
  @spec session(Plug.Conn.t()) :: %{String.t() => boolean()}
  def session(%Plug.Conn{} = conn), do: %{@session_key => framed_request?(conn)}

  @doc "Marks `current_scope` framed when the LiveView session says so. An anonymous page has no scope to mark."
  def on_mount(:framed, _params, session, socket) do
    case {session[@session_key], socket.assigns[:current_scope]} do
      {true, %{} = current_scope} ->
        {:cont, assign(socket, :current_scope, Map.put(current_scope, :framed, true))}

      _other ->
        {:cont, socket}
    end
  end
end
