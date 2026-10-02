defmodule BilimbiWeb.WebhookRateLimit do
  @moduledoc """
  Atomic per-handler, per-node fixed-window admission. Keys are restricted to
  compiled registrations and one unknown-handler bucket at the host boundary,
  so attacker-controlled identifiers cannot grow state.
  Accepted and refused verification attempts both consume admission capacity.
  """
  use GenServer
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def admit(identifier, limit, window_ms),
    do: GenServer.call(__MODULE__, {:admit, identifier, limit, window_ms})

  @impl true
  def init(_opts), do: {:ok, %{}}
  @impl true
  def handle_call({:admit, id, limit, window}, _from, state) do
    now = System.monotonic_time(:millisecond)
    {count, started} = Map.get(state, id, {0, now})
    {count, started} = if started + window <= now, do: {0, now}, else: {count, started}

    if count < limit do
      {:reply, :ok, Map.put(state, id, {count + 1, started})}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end
end
