defmodule Bilimbi.Base.Settings.Cache do
  @moduledoc """
  Small, process-safe read-through cache for setting rows and misses.

  Entries expire after 30 seconds as a guard against writes made outside the
  Settings API. Direct writes should be avoided; multi-node deployments need
  PubSub invalidation in addition to this node-local cache.
  """

  use GenServer

  @table __MODULE__
  @ttl_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, table}
  end

  @spec fetch({String.t(), String.t() | nil, pos_integer() | nil}, (-> term())) :: term()
  def fetch(key, loader) when is_function(loader, 0) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, expires_at, value}] when expires_at > now ->
        value

      _ ->
        value = loader.()
        true = :ets.insert(@table, {key, now + @ttl_ms, value})
        value
    end
  end

  @spec fetch_many([{String.t(), String.t() | nil, pos_integer() | nil}], ([tuple()] -> map())) ::
          %{optional(tuple()) => term()}
  def fetch_many(keys, loader) when is_list(keys) and is_function(loader, 1) do
    now = System.monotonic_time(:millisecond)

    {hits, misses} =
      Enum.reduce(keys, {%{}, []}, fn key, {hits, misses} ->
        case :ets.lookup(@table, key) do
          [{^key, expires_at, value}] when expires_at > now -> {Map.put(hits, key, value), misses}
          _ -> {hits, [key | misses]}
        end
      end)

    case misses do
      [] ->
        hits

      _ ->
        loaded = loader.(misses)

        Enum.reduce(misses, hits, fn key, result ->
          value = Map.get(loaded, key)
          true = :ets.insert(@table, {key, now + @ttl_ms, value})
          Map.put(result, key, value)
        end)
    end
  end

  @spec invalidate(String.t(), String.t() | nil, pos_integer() | nil) :: :ok
  def invalidate(key, scope_type, scope_id) do
    :ets.delete(@table, {key, scope_type, scope_id})
    :ok
  end

  @doc false
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end
end
