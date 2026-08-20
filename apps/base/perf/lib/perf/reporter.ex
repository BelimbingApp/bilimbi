defmodule Bilimbi.Base.Perf.Reporter do
  @moduledoc false

  use GenServer

  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Perf.Sample
  alias Bilimbi.Base.Repo

  @counter_table :bilimbi_base_perf_reporter
  @counter_key :pending
  @dropped_key :dropped
  @default_max_pending 1_000
  @prune_every 100

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

  @doc false
  def stats do
    %{
      pending: counter(@counter_key),
      dropped: counter(@dropped_key),
      max_pending: max_pending()
    }
  rescue
    _error -> %{pending: 0, dropped: 0, max_pending: max_pending()}
  end

  @impl true
  def init(_options) do
    :ets.new(@counter_table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@counter_table, {@counter_key, 0})
    :ets.insert(@counter_table, {@dropped_key, 0})
    :ok = Perf.attach_handlers()
    {:ok, %{accepted: 0}}
  end

  @impl true
  def handle_cast({:record, attributes}, state) do
    accepted =
      try do
        if Perf.recording_enabled?() and Perf.keep_sample?(attributes) do
          case %Sample{} |> Sample.changeset(attributes) |> Repo.insert() do
            {:ok, _sample} -> 1
            {:error, _changeset} -> 0
          end
        else
          0
        end
      rescue
        _error -> 0
      catch
        _kind, _reason -> 0
      after
        release_slot()
      end

    accepted = state.accepted + accepted
    if accepted > 0 and rem(accepted, @prune_every) == 0, do: Perf.prune()
    {:noreply, %{state | accepted: accepted}}
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
      :ets.update_counter(@counter_table, @dropped_key, {2, 1})
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
    case Application.get_env(:bilimbi_base_perf, :max_pending, @default_max_pending) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_max_pending
    end
  end

  defp counter(key), do: :ets.lookup_element(@counter_table, key, 2)
end
