defmodule Bilimbi.Base.Perf.Reporter do
  @moduledoc false

  use GenServer

  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Perf.Sample
  alias Bilimbi.Base.Repo

  @counter_table :bilimbi_base_perf_reporter
  @counter_key :pending
  @default_max_pending 1_000

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec submit(map()) :: :ok
  def submit(attributes) when is_map(attributes) do
    with pid when is_pid(pid) <- Process.whereis(__MODULE__),
         true <- reserve_slot(max_pending()) do
      GenServer.cast(pid, {:record, attributes})
    else
      _unavailable -> :ok
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  @impl true
  def init(_options) do
    :ets.new(@counter_table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@counter_table, {@counter_key, 0})
    :ok = Perf.attach_handlers()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record, attributes}, state) do
    try do
      if Perf.recording_enabled?() and Perf.keep_sample?(attributes) do
        %Sample{}
        |> Sample.changeset(attributes)
        |> Repo.insert()
      end
    rescue
      _error -> :ok
    catch
      _kind, _reason -> :ok
    after
      release_slot()
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    Perf.detach_handlers()
    :ok
  end

  defp reserve_slot(maximum) do
    pending = :ets.update_counter(@counter_table, @counter_key, {2, 1})

    if pending <= maximum do
      true
    else
      release_slot()
      false
    end
  end

  defp release_slot do
    :ets.update_counter(@counter_table, @counter_key, {2, -1, 0, 0})
    :ok
  rescue
    _error -> :ok
  end

  defp max_pending do
    Application.get_env(:bilimbi_base_perf, :max_pending, @default_max_pending)
  end
end
