defmodule Bilimbi.Base.UI.EventAuthorization do
  @moduledoc """
  Host-owned authorization for events in a LiveView process and its components.

  The host installs a socket authorization callback when it mounts a route and
  replaces it on live navigation. Stateful components run in that same process,
  so the callback uses the owning page's identity and requirement without
  trusting component assigns or requiring every component to forward them.
  Pages without a host policy have no callback.
  """

  def install(callback) when is_function(callback, 1) do
    Process.put(__MODULE__, callback)
    :ok
  end

  def authorize(socket) do
    case Process.get(__MODULE__) do
      nil -> {:cont, socket}
      callback -> callback.(socket)
    end
  end
end
