defmodule Bilimbi.Base.Perf.Reporter do
  @moduledoc false

  use GenServer
  import Ecto.Query

  alias Bilimbi.Base.Perf.Sample
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings

  @counter_table :bilimbi_base_perf_reporter
  @counter_key :pending
  @dropped_key :dropped
  @default_max_pending 1_000
  @prune_every 100
  @handler_id "bilimbi-base-perf"
  @request_key {__MODULE__, :request_observation}
  @job_key {__MODULE__, :job_observation}
  @live_view_key {__MODULE__, :live_view_observation}
  @events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]
  @route_pattern ~r|^/[A-Za-z0-9_/:.*-]{0,254}$|
  @live_view_pattern ~r|^liveview:Elixir\.[A-Za-z0-9_.]{1,230}$|
  @worker_pattern ~r|^[a-z0-9][a-z0-9_/-]{0,127}$|

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec submit(map()) :: :ok | {:error, :saturated | :unavailable}
  def submit(attributes) when is_map(attributes) do
    with pid when is_pid(pid) <- Process.whereis(__MODULE__),
         true <- reserve_slot(max_pending()) do
      GenServer.cast(pid, {:record, attributes})
    else
      false -> {:error, :saturated}
      nil -> {:error, :unavailable}
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
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
    if instrumentation_enabled?(), do: attach_handlers()
    {:ok, %{accepted: 0}}
  end

  @impl true
  def handle_cast({:record, attributes}, state) do
    inserted =
      try do
        with_dynamic_repo(fn -> record(attributes) end)
      rescue
        _error -> 0
      catch
        _kind, _reason -> 0
      after
        release_slot()
      end

    accepted = state.accepted + inserted
    if inserted == 1 and rem(accepted, @prune_every) == 0, do: prune()
    {:noreply, %{state | accepted: accepted}}
  end

  @impl true
  def terminate(_reason, _state) do
    detach_handlers()
    :ok
  end

  @spec attach_handlers() :: :ok
  def attach_handlers do
    detach_handlers()
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, make_ref())
  end

  @spec detach_handlers() :: :ok
  def detach_handlers do
    :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  def handle_event([:phoenix, :router_dispatch, :start], measurements, metadata, generation) do
    case route_identity(metadata) do
      {:ok, identity} -> start_observation(@request_key, identity, measurements, generation)
      :error -> clear_observation(@request_key)
    end
  end

  def handle_event([:phoenix, :router_dispatch, terminal], measurements, metadata, generation)
      when terminal in [:stop, :exception] do
    finish_observation(@request_key, "request", terminal, measurements, metadata, generation)
  end

  def handle_event([:oban, :job, :start], measurements, metadata, generation) do
    case worker_identity(metadata) do
      {:ok, identity} -> start_observation(@job_key, identity, measurements, generation)
      :error -> clear_observation(@job_key)
    end
  end

  def handle_event([:oban, :job, terminal], measurements, metadata, generation)
      when terminal in [:stop, :exception] do
    finish_observation(@job_key, "job", terminal, measurements, metadata, generation)
  end

  def handle_event([:phoenix, :live_view, phase, :start], measurements, metadata, generation)
      when phase in [:handle_event, :handle_params] do
    key = {@live_view_key, phase}

    case live_view_identity(metadata) do
      {:ok, identity} -> start_observation(key, identity, measurements, generation)
      :error -> clear_observation(key)
    end
  end

  def handle_event([:phoenix, :live_view, phase, terminal], measurements, metadata, generation)
      when phase in [:handle_event, :handle_params] and terminal in [:stop, :exception] do
    finish_observation(
      {@live_view_key, phase},
      "liveview",
      terminal,
      measurements,
      metadata,
      generation
    )
  end

  def handle_event([:bilimbi, :base, :repo, :query], measurements, _metadata, _generation) do
    duration = query_milliseconds(Map.get(measurements, :total_time, 0))
    accumulate_query(@request_key, duration)
    accumulate_query(@job_key, duration)
    accumulate_query({@live_view_key, :handle_event}, duration)
    accumulate_query({@live_view_key, :handle_params}, duration)
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @doc false
  def recording_enabled? do
    Settings.get("perf.enabled") === true
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  @doc "Deletes expired history and rows beyond the configured global cap."
  @spec prune() :: {:ok, non_neg_integer()} | {:error, :unavailable}
  def prune do
    keep_days = Settings.get("perf.history.keep_days")
    max_rows = Settings.get("perf.history.max_rows")

    if is_integer(keep_days) and keep_days > 0 and is_integer(max_rows) and max_rows > 0 do
      cutoff = DateTime.add(DateTime.utc_now(), -keep_days, :day)
      {expired, _} = Repo.delete_all(from(sample in Sample, where: sample.observed_at < ^cutoff))

      overflow_query =
        from(sample in Sample,
          order_by: [desc: sample.observed_at, desc: sample.id],
          offset: ^max_rows,
          select: sample.id
        )

      {overflow, _} =
        Repo.delete_all(from(sample in Sample, where: sample.id in subquery(overflow_query)))

      {:ok, expired + overflow}
    else
      {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
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
    ArgumentError -> {:error, :unavailable}
  end

  defp max_pending do
    case Application.get_env(:bilimbi_base_perf, :max_pending, @default_max_pending) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_max_pending
    end
  end

  defp instrumentation_enabled? do
    Application.get_env(:bilimbi_base_perf, :instrumentation_enabled, true)
  end

  defp record(attributes) do
    if recording_enabled?() and keep_sample?(attributes) do
      case %Sample{} |> Sample.changeset(attributes) |> Repo.insert() do
        {:ok, _sample} -> 1
        {:error, _changeset} -> 0
      end
    else
      0
    end
  end

  defp with_dynamic_repo(function) do
    previous = Repo.put_dynamic_repo(dynamic_repo())

    try do
      function.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp dynamic_repo do
    case Application.get_env(:bilimbi_base_perf, :get_dynamic_repo) do
      resolver when is_function(resolver, 0) -> resolver.()
      _default -> Repo
    end
  end

  defp counter(key), do: :ets.lookup_element(@counter_table, key, 2)

  defp keep_sample?(attributes) do
    duration = Map.fetch!(attributes, :duration_ms)
    rate = Settings.get("perf.sample_rate")

    valid_number?(duration) and valid_rate?(rate) and
      eligible_duration?(attributes, duration) and sampled?(rate)
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp start_observation(key, identity, measurements, generation) do
    clear_observation(key)

    Process.put(key, %{
      identity: identity,
      started_at: Map.get(measurements, :monotonic_time, System.monotonic_time()),
      generation: generation,
      db_count: 0,
      db_duration_ms: 0
    })

    :ok
  end

  defp finish_observation(key, kind, terminal, measurements, metadata, generation) do
    case Process.delete(key) do
      %{identity: identity, generation: ^generation} = observation ->
        submit(%{
          kind: kind,
          identity: identity,
          outcome: outcome(kind, terminal, metadata),
          duration_ms: observation_duration(observation, measurements),
          db_duration_ms: observation.db_duration_ms,
          db_count: observation.db_count,
          response_size_class: response_size_class(kind, metadata),
          memory_bytes: :erlang.memory(:total),
          run_queue: :erlang.statistics(:run_queue),
          observed_at: DateTime.utc_now()
        })

      _missing ->
        :ok
    end
  rescue
    _error ->
      clear_observation(key)
      :ok
  catch
    _kind, _reason ->
      clear_observation(key)
      :ok
  end

  defp accumulate_query(key, duration) do
    case Process.get(key) do
      %{db_count: count, db_duration_ms: total} = observation ->
        Process.put(key, %{observation | db_count: count + 1, db_duration_ms: total + duration})

      _missing ->
        :ok
    end
  end

  defp query_milliseconds(duration) when is_integer(duration) and duration > 0 do
    native_per_millisecond = System.convert_time_unit(1, :millisecond, :native)
    div(duration + native_per_millisecond - 1, native_per_millisecond)
  end

  defp query_milliseconds(_duration), do: 0

  defp clear_observation(key) do
    Process.delete(key)
    :ok
  end

  defp route_identity(%{route: route}) when is_binary(route) do
    if Regex.match?(@route_pattern, route) and not String.contains?(route, "?") do
      {:ok, route}
    else
      :error
    end
  end

  defp route_identity(_metadata), do: :error

  defp worker_identity(%{job: %{meta: %{"bilimbi_worker_id" => worker_id}}})
       when is_binary(worker_id) do
    if Regex.match?(@worker_pattern, worker_id), do: {:ok, worker_id}, else: :error
  end

  defp worker_identity(_metadata), do: :error

  defp live_view_identity(%{socket: %{view: view}}) when is_atom(view) do
    identity = "liveview:" <> Atom.to_string(view)

    if byte_size(identity) <= 255 and Regex.match?(@live_view_pattern, identity) do
      {:ok, identity}
    else
      :error
    end
  end

  defp live_view_identity(_metadata), do: :error

  defp observation_duration(observation, measurements) do
    case Map.get(measurements, :duration) do
      duration when is_integer(duration) and duration >= 0 -> native_milliseconds(duration)
      _missing -> native_milliseconds(System.monotonic_time() - observation.started_at)
    end
  end

  defp native_milliseconds(value) when is_integer(value) and value >= 0 do
    System.convert_time_unit(value, :native, :millisecond)
  end

  defp native_milliseconds(_value), do: 0

  defp outcome("request", :stop, %{conn: %{status: status}})
       when is_integer(status) and status < 400,
       do: "ok"

  defp outcome("liveview", :stop, %{socket: %{view: view}}) when is_atom(view), do: "ok"
  defp outcome("liveview", :stop, _metadata), do: "error"
  defp outcome("liveview", :exception, _metadata), do: "error"

  defp outcome("request", :stop, _metadata), do: "error"
  defp outcome("request", :exception, _metadata), do: "error"

  defp outcome("job", :exception, %{state: state}) when state in [:discard, :discarded],
    do: "discarded"

  defp outcome("job", :exception, _metadata), do: "error"
  defp outcome("job", :stop, %{state: state}) when state in [:cancel, :cancelled], do: "cancelled"

  defp outcome("job", :stop, %{state: state}) when state in [:discard, :discarded],
    do: "discarded"

  defp outcome("job", :stop, %{state: state}) when state in [:failure, :error], do: "error"
  defp outcome("job", :stop, _metadata), do: "ok"

  defp response_size_class("request", %{conn: %{resp_body: body}}) when is_binary(body) do
    case byte_size(body) do
      size when size < 1_024 -> "under_1k"
      size when size < 10_240 -> "1k_10k"
      size when size < 102_400 -> "10k_100k"
      _large -> "over_100k"
    end
  end

  defp response_size_class(_kind, _metadata), do: nil

  defp valid_number?(value), do: is_integer(value) and value >= 0
  defp valid_rate?(value), do: is_number(value) and value >= 0 and value <= 1
  defp eligible_duration?(%{kind: "runtime"}, _duration), do: true

  defp eligible_duration?(_attributes, duration) do
    case Settings.get("perf.minimum_duration_ms") do
      minimum when is_integer(minimum) and minimum >= 0 -> duration >= minimum
      _invalid -> false
    end
  end

  defp sampled?(1), do: true
  defp sampled?(1.0), do: true
  defp sampled?(rate) when rate == 0, do: false
  defp sampled?(rate), do: :rand.uniform() <= rate
end
