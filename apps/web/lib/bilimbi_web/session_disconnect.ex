defmodule BilimbiWeb.SessionDisconnect do
  @moduledoc """
  Ends the live sockets of a durable session that ended.

  Every LiveView socket of a signed-in browser carries its session's
  `live_socket_id` (`BilimbiWeb.UserAuth.live_socket_id/1`) from the cookie
  session, and Phoenix closes a transport when `"disconnect"` is broadcast on
  that id. Base Session reports explicit deletions and terminations: logout,
  an operator ending a listed session, Core User ending
  a user's sessions after a password reset or a change of affiliation. This
  process is the host's one subscriber and turns each termination into that
  broadcast, so every open tab of the session reconnects and is refused at
  mount instead of waiting for its next action.

  The per-action re-proof in `BilimbiWeb.RouteAccess` does not depend on this
  message arriving: a page that is still connected when it next acts re-reads
  the session row and ends itself. This closes the idle tabs.
  """

  use GenServer

  alias Bilimbi.Base.Session

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case Session.subscribe_terminations() do
      :ok -> {:ok, %{}}
      {:error, reason} -> {:stop, {:session_terminations_unavailable, reason}}
    end
  end

  @impl true
  def handle_info({:session_terminated, session_id}, state) when is_binary(session_id) do
    :ok =
      BilimbiWeb.Endpoint.broadcast(
        BilimbiWeb.UserAuth.live_socket_id(session_id),
        "disconnect",
        %{}
      )

    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
