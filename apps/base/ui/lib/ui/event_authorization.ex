defmodule Bilimbi.Base.UI.EventAuthorization do
  @moduledoc """
  Host-owned authorization for events in a LiveView process and its components.

  The host installs a socket authorization callback when it mounts a route and
  replaces it on live navigation. Stateful components run in that same process,
  so the callback uses the owning page's identity and requirement without
  trusting component assigns or requiring every component to forward them.
  Pages without a host policy have no callback.

  A page that authorizes a business target can add a constraint with
  `constrain/1`. Components run it after the host refreshes identity, so an
  employer or other target cannot retain access after reach is revoked.
  Replacing the host callback during navigation preserves this page constraint;
  navigating to a different LiveView starts a new process and policy.
  """

  def install(callback) when is_function(callback, 1) do
    Process.put(__MODULE__, callback)
    :ok
  end

  def constrain(callback) when is_function(callback, 1) do
    Process.put({__MODULE__, :constraint}, callback)
    :ok
  end

  def authorize(socket) do
    with {:cont, socket} <- run(Process.get(__MODULE__), socket),
         do: run(Process.get({__MODULE__, :constraint}), socket)
  end

  defp run(nil, socket), do: {:cont, socket}
  defp run(callback, socket), do: callback.(socket)
end
