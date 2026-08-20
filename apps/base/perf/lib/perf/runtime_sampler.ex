defmodule Bilimbi.Base.Perf.RuntimeSampler do
  @moduledoc false

  use GenServer

  alias Bilimbi.Base.Perf.Reporter

  @default_interval 60_000

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc false
  @spec sample_now() :: :ok
  def sample_now do
    Reporter.submit(sample())
  end

  @impl true
  def init(_options) do
    schedule_sample()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sample, state) do
    sample_now()
    schedule_sample()
    {:noreply, state}
  end

  defp sample do
    %{
      kind: "runtime",
      identity: "beam",
      outcome: "ok",
      duration_ms: 0,
      db_duration_ms: 0,
      db_count: 0,
      memory_bytes: :erlang.memory(:total),
      run_queue: :erlang.statistics(:run_queue),
      observed_at: DateTime.utc_now()
    }
  end

  defp schedule_sample do
    Process.send_after(self(), :sample, interval())
  end

  defp interval do
    case Application.get_env(:bilimbi_base_perf, :runtime_sample_interval, @default_interval) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_interval
    end
  end
end
