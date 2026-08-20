defmodule Bilimbi.Base.Perf do
  @moduledoc """
  Bounded, redacted operational performance history.

  Telemetry is reduced at ingress to stable route or worker identity, outcome,
  timings, counts, coarse response size, and aggregate runtime pressure. The
  recorder never stores telemetry metadata, SQL, arguments, identifiers, or
  exception details. Recording failure is isolated from observed work.
  """

  import Ecto.Query

  alias Bilimbi.Base.Perf.Reporter
  alias Bilimbi.Base.Perf.Sample
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings

  @handler_id "bilimbi-base-perf"
  @request_key {__MODULE__, :request_observation}
  @job_key {__MODULE__, :job_observation}
  @events [
    [:phoenix, :router_dispatch, :start],
    [:phoenix, :router_dispatch, :stop],
    [:phoenix, :router_dispatch, :exception],
    [:bilimbi, :repo, :query],
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]
  @page_sizes [25, 50, 100, 300]
  @route_pattern ~r|^/[A-Za-z0-9_/:.*-]{0,254}$|
  @worker_pattern ~r|^[a-z0-9][a-z0-9_/-]{0,127}$|

  @spec attach_handlers() :: :ok
  def attach_handlers do
    detach_handlers()
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  @spec detach_handlers() :: :ok
  def detach_handlers do
    :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  def handle_event([:phoenix, :router_dispatch, :start], measurements, metadata, _config) do
    case route_identity(metadata) do
      {:ok, identity} -> start_observation(@request_key, identity, measurements)
      :error -> clear_observation(@request_key)
    end
  end

  def handle_event([:phoenix, :router_dispatch, terminal], measurements, metadata, _config)
      when terminal in [:stop, :exception] do
    finish_observation(@request_key, "request", terminal, measurements, metadata)
  end

  def handle_event([:oban, :job, :start], measurements, metadata, _config) do
    case worker_identity(metadata) do
      {:ok, identity} -> start_observation(@job_key, identity, measurements)
      :error -> clear_observation(@job_key)
    end
  end

  def handle_event([:oban, :job, terminal], measurements, metadata, _config)
      when terminal in [:stop, :exception] do
    finish_observation(@job_key, "job", terminal, measurements, metadata)
  end

  def handle_event([:bilimbi, :repo, :query], measurements, _metadata, _config) do
    duration = native_milliseconds(Map.get(measurements, :total_time, 0))
    accumulate_query(@request_key, duration)
    accumulate_query(@job_key, duration)
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

  @doc false
  def keep_sample?(attributes) do
    duration = Map.fetch!(attributes, :duration_ms)
    minimum = Settings.get("perf.minimum_duration_ms")
    rate = Settings.get("perf.sample_rate")

    valid_number?(duration) and is_integer(minimum) and minimum >= 0 and
      valid_rate?(rate) and duration >= minimum and sampled?(rate)
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  @doc "Returns one bounded page without exposing captured telemetry metadata."
  @spec list_samples(keyword()) :: {:ok, map()} | {:error, :invalid_options | :unavailable}
  def list_samples(options \\ [])

  def list_samples(options) when is_list(options) do
    with {:ok, filters} <- validate_list_options(options) do
      query = filtered_samples(filters)
      total = Repo.aggregate(query, :count, :id)

      entries =
        query
        |> order_by([sample], desc: sample.observed_at, desc: sample.id)
        |> limit(^filters.page_size)
        |> offset(^((filters.page - 1) * filters.page_size))
        |> Repo.all()

      {:ok, %{entries: entries, total: total, page: filters.page, page_size: filters.page_size}}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def list_samples(_options), do: {:error, :invalid_options}

  @doc "Returns bounded store and recorder health without inferring health from no traffic."
  @spec diagnostics() :: map()
  def diagnostics do
    reporter? = is_pid(Process.whereis(Reporter))
    latest = Repo.one(from(sample in Sample, select: max(sample.observed_at)))
    count = Repo.aggregate(Sample, :count, :id)

    %{
      recorder: if(reporter?, do: :available, else: :unavailable),
      store: :available,
      recording: if(recording_enabled?(), do: :enabled, else: :disabled),
      samples: count,
      last_observed_at: latest
    }
  rescue
    _error ->
      %{
        recorder: if(is_pid(Process.whereis(Reporter)), do: :available, else: :unavailable),
        store: :unavailable,
        recording: :unknown,
        samples: nil,
        last_observed_at: nil
      }
  catch
    :exit, _reason ->
      %{
        recorder: :unavailable,
        store: :unavailable,
        recording: :unknown,
        samples: nil,
        last_observed_at: nil
      }
  end

  @doc "Compares route/job latency across two explicit, non-overlapping windows."
  @spec regressions(keyword()) :: {:ok, [map()]} | {:error, :invalid_options | :unavailable}
  def regressions(options) when is_list(options) do
    with {:ok, windows} <- validate_regression_options(options),
         {:ok, threshold} <- slow_threshold() do
      baseline = window_stats(windows.baseline_from, windows.baseline_to, windows.min_samples)
      current = window_stats(windows.current_from, windows.current_to, windows.min_samples)

      rows =
        current
        |> Enum.flat_map(fn {identity, current_stats} ->
          case Map.fetch(baseline, identity) do
            {:ok, baseline_stats} ->
              [regression_row(identity, baseline_stats, current_stats, threshold)]

            :error ->
              []
          end
        end)
        |> Enum.filter(&(&1.current_p95_ms >= threshold))
        |> Enum.sort_by(&{-&1.delta_percent, &1.kind, &1.identity})
        |> Enum.take(windows.limit)

      {:ok, rows}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def regressions(_options), do: {:error, :invalid_options}

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

  defp start_observation(key, identity, measurements) do
    clear_observation(key)

    Process.put(key, %{
      identity: identity,
      started_at: Map.get(measurements, :monotonic_time, System.monotonic_time()),
      db_count: 0,
      db_duration_ms: 0
    })

    :ok
  end

  defp finish_observation(key, kind, terminal, measurements, metadata) do
    case Process.delete(key) do
      %{identity: identity} = observation ->
        Reporter.submit(%{
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
       when is_integer(status) and status < 500,
       do: "ok"

  defp outcome("request", :stop, _metadata), do: "error"
  defp outcome("request", :exception, _metadata), do: "error"
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
  defp sampled?(1), do: true
  defp sampled?(1.0), do: true
  defp sampled?(rate) when rate == 0, do: false
  defp sampled?(rate), do: :rand.uniform() <= rate

  defp validate_list_options(options) do
    allowed = [:page, :page_size, :kind, :identity, :outcome, :from, :to]
    page = Keyword.get(options, :page, 1)
    page_size = Keyword.get(options, :page_size, 25)
    kind = Keyword.get(options, :kind)
    identity = Keyword.get(options, :identity)
    outcome = Keyword.get(options, :outcome)
    from = Keyword.get(options, :from)
    to = Keyword.get(options, :to)

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         is_integer(page) and page > 0 and page_size in @page_sizes and
         (is_nil(kind) or kind in ~w(request job runtime)) and
         (is_nil(identity) or valid_identity_filter?(identity)) and
         (is_nil(outcome) or outcome in ~w(ok error cancelled discarded)) and
         (is_nil(from) or match?(%DateTime{}, from)) and (is_nil(to) or match?(%DateTime{}, to)) do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         kind: kind,
         identity: identity,
         outcome: outcome,
         from: from,
         to: to
       }}
    else
      {:error, :invalid_options}
    end
  end

  defp valid_identity_filter?(identity), do: is_binary(identity) and byte_size(identity) in 1..255

  defp filtered_samples(filters) do
    Sample
    |> maybe_filter(:kind, filters.kind)
    |> maybe_filter(:identity, filters.identity)
    |> maybe_filter(:outcome, filters.outcome)
    |> maybe_filter(:from, filters.from)
    |> maybe_filter(:to, filters.to)
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :kind, value), do: where(query, [sample], sample.kind == ^value)

  defp maybe_filter(query, :identity, value),
    do: where(query, [sample], sample.identity == ^value)

  defp maybe_filter(query, :outcome, value), do: where(query, [sample], sample.outcome == ^value)
  defp maybe_filter(query, :from, value), do: where(query, [sample], sample.observed_at >= ^value)
  defp maybe_filter(query, :to, value), do: where(query, [sample], sample.observed_at < ^value)

  defp validate_regression_options(options) do
    allowed = [:baseline_from, :baseline_to, :current_from, :current_to, :min_samples, :limit]
    baseline_from = Keyword.get(options, :baseline_from)
    baseline_to = Keyword.get(options, :baseline_to)
    current_from = Keyword.get(options, :current_from)
    current_to = Keyword.get(options, :current_to)
    min_samples = Keyword.get(options, :min_samples, 20)
    limit = Keyword.get(options, :limit, 25)

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         match?(%DateTime{}, baseline_from) and match?(%DateTime{}, baseline_to) and
         match?(%DateTime{}, current_from) and match?(%DateTime{}, current_to) and
         DateTime.before?(baseline_from, baseline_to) and
         DateTime.before?(current_from, current_to) and
         DateTime.compare(baseline_to, current_from) in [:lt, :eq] and
         is_integer(min_samples) and min_samples in 5..100_000 and
         is_integer(limit) and limit in 1..100 do
      {:ok,
       %{
         baseline_from: baseline_from,
         baseline_to: baseline_to,
         current_from: current_from,
         current_to: current_to,
         min_samples: min_samples,
         limit: limit
       }}
    else
      {:error, :invalid_options}
    end
  end

  defp slow_threshold do
    case Settings.get("perf.slow_threshold_ms") do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, :unavailable}
    end
  end

  defp window_stats(from, to, minimum) do
    from(sample in Sample,
      where: sample.observed_at >= ^from and sample.observed_at < ^to,
      group_by: [sample.kind, sample.identity],
      having: count(sample.id) >= ^minimum,
      select: {
        {sample.kind, sample.identity},
        %{
          samples: count(sample.id),
          average: avg(sample.duration_ms),
          p95: fragment("percentile_cont(0.95) WITHIN GROUP (ORDER BY ?)", sample.duration_ms)
        }
      }
    )
    |> Repo.all()
    |> Map.new()
  end

  defp regression_row({kind, identity}, baseline, current, threshold) do
    baseline_average = numeric_float(baseline.average)
    current_average = numeric_float(current.average)

    delta =
      if baseline_average == 0, do: 0.0, else: (current_average / baseline_average - 1) * 100

    %{
      kind: kind,
      identity: identity,
      baseline_samples: baseline.samples,
      current_samples: current.samples,
      baseline_average_ms: baseline_average,
      current_average_ms: current_average,
      current_p95_ms: numeric_float(current.p95),
      delta_percent: Float.round(delta, 1),
      slow?: numeric_float(current.p95) >= threshold
    }
  end

  defp numeric_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric_float(value) when is_integer(value), do: value * 1.0
  defp numeric_float(value) when is_float(value), do: value
end
