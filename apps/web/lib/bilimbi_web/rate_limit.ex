defmodule BilimbiWeb.RateLimit do
  @moduledoc """
  Sliding-window throttle for credential endpoints.

  Mirrors Belimbing's login throttle contract (`Auth/Login.php`): at most
  five attempts per email+IP key inside the window, then a lockout that
  reports how many seconds remain. Successful authentication resets the key.

  This is request coordination, not a business rule: the credential check
  itself lives in `Bilimbi.Core.User`. State is per-node ETS, which matches
  the single-node development and baseline deployment shape.
  """

  use GenServer

  @table __MODULE__.Table
  # Belimbing: RateLimiter::tooManyAttempts(key, 5) with a 60-second decay.
  @default_limit 5
  @default_window_ms 60_000
  @sweep_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Whether another attempt may proceed. Returns `:allow` or
  `{:deny, retry_in_seconds}` with the ceiling of the remaining window.
  """
  @spec attempt_allowed?(term(), pos_integer(), pos_integer()) ::
          :allow | {:deny, pos_integer()}
  def attempt_allowed?(key, limit \\ @default_limit, window_ms \\ @default_window_ms) do
    now = System.monotonic_time(:millisecond)

    case lookup(key) do
      timestamps when length(timestamps) < limit ->
        :allow

      timestamps ->
        oldest = Enum.min(timestamps)
        retry_in_ms = oldest + window_ms - now

        if retry_in_ms <= 0 do
          :allow
        else
          {:deny, max(1, ceil(retry_in_ms / 1_000))}
        end
    end
  end

  @doc "Records one failed attempt against the key."
  @spec record_attempt(term(), pos_integer()) :: :ok
  def record_attempt(key, window_ms \\ @default_window_ms) do
    GenServer.call(__MODULE__, {:record, key, window_ms})
  end

  @doc "Clears the key after a successful authentication."
  @spec reset(term()) :: :ok
  def reset(key) do
    GenServer.call(__MODULE__, {:reset, key})
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, table}
  end

  @impl true
  def handle_call({:record, key, window_ms}, _from, table) do
    now = System.monotonic_time(:millisecond)
    timestamps = [now | lookup(key)] |> Enum.filter(&(&1 + window_ms > now))
    :ets.insert(@table, {key, timestamps})
    {:reply, :ok, table}
  end

  def handle_call({:reset, key}, _from, table) do
    :ets.delete(@table, key)
    {:reply, :ok, table}
  end

  @impl true
  def handle_info(:sweep, table) do
    now = System.monotonic_time(:millisecond)

    # Drop keys whose stamps have all aged past the window; stale keys would
    # otherwise accumulate for every mistyped email.
    :ets.foldl(
      fn {key, timestamps}, :ok ->
        if Enum.all?(timestamps, &(&1 + @default_window_ms <= now)) do
          :ets.delete(@table, key)
        end

        :ok
      end,
      :ok,
      @table
    )

    schedule_sweep()
    {:noreply, table}
  end

  defp lookup(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, timestamps}] -> Enum.filter(timestamps, &(&1 + @default_window_ms > now))
      [] -> []
    end
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end
