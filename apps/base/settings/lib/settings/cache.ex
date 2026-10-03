defmodule Bilimbi.Base.Settings.Cache do
  @moduledoc """
  Node-local read-through cache for setting rows and misses.

  Entries expire after 30 seconds and are periodically reclaimed. Multi-node
  deployments require PubSub invalidation in addition to this cache.
  """

  use GenServer

  @table __MODULE__
  @ttl_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    Process.send_after(self(), :sweep, @ttl_ms)
    {:ok, make_ref()}
  end

  @spec fetch(tuple(), (-> term())) :: term()
  def fetch(key, loader) when is_function(loader, 0) do
    case GenServer.call(__MODULE__, {:lookup, key}) do
      {:hit, value} ->
        value

      {:miss, generation} ->
        value = loader.()
        :ok = GenServer.call(__MODULE__, {:publish, key, generation, value})
        value
    end
  end

  @spec invalidate(String.t(), String.t() | nil, pos_integer() | nil) :: :ok
  def invalidate(key, scope_type, scope_id) do
    GenServer.call(__MODULE__, {:invalidate, {key, scope_type, scope_id}})
  end

  @doc false
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def handle_call({:lookup, key}, _from, generation) do
    now = System.monotonic_time(:millisecond)

    result =
      case :ets.lookup(@table, key) do
        [{^key, expires_at, value}] when expires_at > now -> {:hit, value}
        _ -> {:miss, generation}
      end

    {:reply, result, generation}
  end

  def handle_call({:publish, key, expected, value}, _from, generation) do
    if expected == generation do
      :ets.insert(@table, {key, System.monotonic_time(:millisecond) + @ttl_ms, value})
    end

    {:reply, :ok, generation}
  end

  def handle_call({:invalidate, key}, _from, _generation) do
    :ets.delete(@table, key)
    {:reply, :ok, make_ref()}
  end

  def handle_call(:clear, _from, _generation) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, make_ref()}
  end

  @impl true
  def handle_info(:sweep, generation) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:"$1", :"$2", :"$3"}, [{:"=<", :"$2", now}], [true]}])
    Process.send_after(self(), :sweep, @ttl_ms)
    {:noreply, generation}
  end
end
