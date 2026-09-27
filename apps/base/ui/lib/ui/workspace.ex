defmodule Bilimbi.Base.UI.Workspace do
  @moduledoc """
  The follow channel between the tiles of one tiled workspace.

  A workspace is one signed-in browser tab showing several pages in tiles.
  Selecting a record in one tile should be able to steer another, so the
  host and every page in its tiles share one PubSub topic,
  `workspace:<tenant_id>:<user_id>:<token>`. The tenant and user come from
  each process's own `current_scope`, never from the browser, so a page can
  only ever reach the workspace of the account it runs as; the token only
  tells one of that account's workspaces from another.

  The host puts the token in each frame's URL as `?ws=<token>`. The Web
  host copies it from a framed request into the signed LiveView session
  (`BilimbiWeb.FramedRender.session/1`), which live navigation inside the
  frame keeps, and `on_mount/4` reads it back on every page of the
  `live_session`. A page opened on its own carries no token and this module
  does nothing for it.

  Three messages travel on the topic, all plain facts:

    * `{:workspace_joined}` from a page that has mounted in a tile;
    * `{:workspace_fact, %{kind: kind, id: id}}` from a page that opened or
      selected a record, sent by `announce/2`. `kind` is the stable module
      id that owns the record (`"core/company"`), the same vocabulary
      descriptors and menu items use;
    * `{:workspace_follows, kinds}` from the host: the kinds some tile
      follows, sent on every change and after every join.

  A page opts in with `<.record_link>` for a row and `announce/2` at mount.
  Both read the page's `@workspace` assign, which `on_mount/4` sets to
  `nil` outside a workspace, so the same template serves the page alone
  and in a tile. A row selection is decided when it is clicked: announced
  when some tile follows the kind, otherwise a navigation to the record's
  page, so a streamed row need not re-render when the follows change. The
  host is `Bilimbi.Base.Tiling.Web.WorkspaceLive`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView

  @session_key "bilimbi_workspace"
  @param "ws"
  @token ~r/\A[A-Za-z0-9_-]{16}\z/
  @kind ~r{\A[a-z][a-z0-9_]*/[a-z][a-z0-9_]*\z}

  @typedoc "What a page in a tile knows about its workspace."
  @type t :: %{token: String.t(), topic: String.t(), follows: [String.t()]}

  @typedoc "A record a page opened or selected."
  @type fact :: %{kind: String.t(), id: pos_integer() | String.t()}

  # ------------------------------------------------------------------
  # The token and its URL form
  # ------------------------------------------------------------------

  @doc """
  The token of a workspace host, derived from its LiveView id.

  The id is the one value both renders of a host page share: the
  disconnected render writes it into the root element and the client
  joins with it, so the frames written by the first render and the topic
  the connected process subscribes to name the same workspace.
  """
  @spec host_token(String.t()) :: String.t()
  def host_token(socket_id) when is_binary(socket_id) do
    :sha256
    |> :crypto.hash(socket_id)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end

  @doc "Whether `token` has the shape `host_token/1` produces."
  @spec token?(term()) :: boolean()
  def token?(token) when is_binary(token), do: Regex.match?(@token, token)
  def token?(_token), do: false

  @doc "`path` with the workspace token added to its query, for a frame's URL."
  @spec frame_url(String.t(), String.t()) :: String.t()
  def frame_url(path, token) when is_binary(path) and is_binary(token) do
    uri = URI.parse(path)
    query = (uri.query || "") |> URI.decode_query() |> Map.put(@param, token)
    URI.to_string(%{uri | query: URI.encode_query(query)})
  end

  @doc """
  `path` without the workspace token a frame's report carries. A tile's
  path in the tree and in a saved layout never names a token.
  """
  @spec strip_token(String.t()) :: String.t()
  def strip_token(path) when is_binary(path) do
    uri = URI.parse(path)

    query =
      case uri.query do
        nil -> nil
        query -> query |> URI.decode_query() |> Map.delete(@param) |> encode_query()
      end

    URI.to_string(%{uri | query: query})
  end

  defp encode_query(map) when map_size(map) == 0, do: nil
  defp encode_query(map), do: URI.encode_query(map)

  @doc """
  The LiveView session entry carrying the token of a framed request, or an
  empty map. The Web host merges it into the session MFA of every
  discovered `live_session`, for framed requests only.
  """
  @spec session(Plug.Conn.t()) :: %{optional(String.t()) => String.t()}
  def session(%Plug.Conn{} = conn) do
    token = Plug.Conn.fetch_query_params(conn).query_params[@param]
    if token?(token), do: %{@session_key => token}, else: %{}
  end

  @doc "The PubSub topic of one workspace."
  @spec topic(pos_integer(), pos_integer(), String.t()) :: String.t()
  def topic(tenant_id, user_id, token)
      when is_integer(tenant_id) and is_integer(user_id) and is_binary(token) do
    "workspace:#{tenant_id}:#{user_id}:#{token}"
  end

  @doc """
  The topic of the workspace `current_scope` runs in, given the token. The
  scope is the page's own, so the topic can only name that account.
  """
  @spec topic_for(map(), String.t()) :: String.t() | nil
  def topic_for(%{scope: %{tenant: %{id: tenant_id}}} = current_scope, token)
      when is_integer(tenant_id) do
    case current_scope[:user] do
      %{"user_id" => user_id} when is_integer(user_id) -> topic(tenant_id, user_id, token)
      _other -> nil
    end
  end

  def topic_for(_current_scope, _token), do: nil

  # ------------------------------------------------------------------
  # PubSub
  # ------------------------------------------------------------------

  @doc "Subscribes the calling process to a workspace topic."
  @spec subscribe(String.t()) :: :ok | {:error, :pubsub_unavailable}
  def subscribe(topic) when is_binary(topic) do
    with_pubsub(fn server -> Phoenix.PubSub.subscribe(server, topic) end)
  end

  @doc "Sends `message` to every process on a workspace topic."
  @spec broadcast(String.t(), term()) :: :ok | {:error, :pubsub_unavailable}
  def broadcast(topic, message) when is_binary(topic) do
    with_pubsub(fn server -> Phoenix.PubSub.broadcast(server, topic, message) end)
  end

  # A configured but absent PubSub server is a deployment fault, not a
  # reason for a page to crash: the page works, and only the channel is
  # silent. No server configured means the channel is off.
  defp with_pubsub(fun) do
    case Application.get_env(:bilimbi_base_ui, :pubsub_server) do
      nil ->
        :ok

      server ->
        try do
          fun.(server)
        rescue
          ArgumentError -> {:error, :pubsub_unavailable}
        catch
          :exit, _reason -> {:error, :pubsub_unavailable}
        end
    end
  end

  # ------------------------------------------------------------------
  # The page side
  # ------------------------------------------------------------------

  @doc """
  Attaches a page to the workspace named in its LiveView session.

  With a token and a signed-in scope the page gets a `@workspace` assign,
  subscribes to the topic once connected, says it joined, follows the
  host's `{:workspace_follows, kinds}` messages, and answers the
  `workspace:select` event `<.record_link>` sends: an announcement when
  some tile follows the kind, otherwise a navigation to the record's page.
  Without a token the assign is `nil` and nothing else happens.
  """
  def on_mount(:attach, _params, session, socket) do
    token = session[@session_key]

    with true <- token?(token),
         %{} = current_scope <- socket.assigns[:current_scope],
         topic when is_binary(topic) <- topic_for(current_scope, token) do
      if LiveView.connected?(socket) do
        subscribe(topic)
        broadcast(topic, {:workspace_joined})
      end

      {:cont,
       socket
       |> assign(:workspace, %{token: token, topic: topic, follows: []})
       |> LiveView.attach_hook(:workspace_follows, :handle_info, &handle_info/2)
       |> LiveView.attach_hook(:workspace_select, :handle_event, &handle_event/3)}
    else
      _other -> {:cont, assign(socket, :workspace, nil)}
    end
  end

  defp handle_info({:workspace_follows, kinds}, socket) when is_list(kinds) do
    workspace = %{socket.assigns.workspace | follows: Enum.filter(kinds, &kind?/1)}
    {:halt, assign(socket, :workspace, workspace)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("workspace:select", %{"kind" => kind, "id" => id} = params, socket) do
    if followed?(socket.assigns.workspace, kind),
      do: {:halt, announce(socket, %{kind: kind, id: id})},
      else: {:halt, open_record(socket, params["path"])}
  end

  defp handle_event("workspace:select", _params, socket), do: {:halt, socket}
  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # The navigation the row's link would have made. The path came back from
  # the browser, so it must be a page this deployment serves.
  defp open_record(socket, path) when is_binary(path) do
    case Bilimbi.Base.UI.RouteContract.fetch_route(path) do
      {:ok, _route} -> LiveView.push_navigate(socket, to: path)
      :error -> socket
    end
  end

  defp open_record(socket, _path), do: socket

  @doc """
  Tells the workspace that the page opened or selected a record.

  A fact, not a command: the host decides which tiles follow `kind`. A page
  outside a workspace, a disconnected render, or a malformed fact announces
  nothing. Returns the socket so the call sits in a pipeline.
  """
  @spec announce(LiveView.Socket.t(), fact()) :: LiveView.Socket.t()
  def announce(%LiveView.Socket{} = socket, %{kind: kind, id: id} = fact) do
    with %{topic: topic} <- socket.assigns[:workspace],
         true <- LiveView.connected?(socket),
         true <- fact?(fact) do
      broadcast(topic, {:workspace_fact, %{kind: kind, id: id}})
    end

    socket
  end

  @doc """
  Whether `fact` names a kind and a record id a host may act on. The host
  checks what arrives on the topic with this too, since any process of the
  account could have sent it.
  """
  @spec fact?(term()) :: boolean()
  def fact?(%{kind: kind, id: id}), do: kind?(kind) and id?(id)
  def fact?(_fact), do: false

  @doc "Whether some tile of the page's workspace follows records of `kind`."
  @spec followed?(t() | nil, String.t()) :: boolean()
  def followed?(%{follows: follows}, kind) when is_list(follows), do: kind in follows
  def followed?(_workspace, _kind), do: false

  @doc "Whether `kind` is a stable module id such as `core/company`."
  @spec kind?(term()) :: boolean()
  def kind?(kind) when is_binary(kind), do: Regex.match?(@kind, kind)
  def kind?(_kind), do: false

  # A record id is the integer a schema carries, or the string form a
  # `phx-value-id` attribute sends back; either fills one path segment.
  defp id?(id) when is_integer(id) and id > 0, do: true

  defp id?(id) when is_binary(id),
    do: id != "" and byte_size(id) <= 64 and not (id =~ ~r{[/?#\s]})

  defp id?(_id), do: false
end
