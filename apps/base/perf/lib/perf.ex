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

  @page_sizes [25, 50, 100, 300]

  @doc false
  @spec handle_event([atom()], map(), map(), term()) :: term()
  def handle_event(event, measurements, metadata, generation) do
    Reporter.handle_event(event, measurements, metadata, generation)
  end

  @doc false
  @spec recording_enabled?() :: boolean()
  def recording_enabled?, do: Reporter.recording_enabled?()

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

    reporter_stats = Reporter.stats()

    %{
      recorder: recorder_status(reporter?, reporter_stats),
      store: :available,
      recording: if(recording_enabled?(), do: :enabled, else: :disabled),
      samples: count,
      last_observed_at: latest,
      pending: reporter_stats.pending,
      dropped: reporter_stats.dropped,
      max_pending: reporter_stats.max_pending
    }
  rescue
    _error ->
      %{
        recorder: if(is_pid(Process.whereis(Reporter)), do: :available, else: :unavailable),
        store: :unavailable,
        recording: :unknown,
        samples: nil,
        last_observed_at: nil,
        pending: nil,
        dropped: nil,
        max_pending: nil
      }
  catch
    :exit, _reason ->
      %{
        recorder: :unavailable,
        store: :unavailable,
        recording: :unknown,
        samples: nil,
        last_observed_at: nil,
        pending: nil,
        dropped: nil,
        max_pending: nil
      }
  end

  @doc "Returns one redacted status string for System diagnostics."
  @spec health_status() :: String.t()
  def health_status do
    case diagnostics() do
      %{recorder: recorder, store: :available, pending: pending, dropped: dropped}
      when recorder in [:available, :degraded] and is_integer(pending) and is_integer(dropped) ->
        "#{status_label(recorder)} (#{pending} pending, #{dropped} dropped)"

      _unavailable ->
        "Unavailable"
    end
  end

  @doc "Compares route/job latency across two explicit, non-overlapping windows."
  @spec regressions(keyword()) :: {:ok, [map()]} | {:error, :invalid_options | :unavailable}
  def regressions(options) when is_list(options) do
    with {:ok, windows} <- validate_regression_options(options),
         {:ok, threshold} <- slow_threshold() do
      {:ok, regression_rows(windows, threshold)}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def regressions(_options), do: {:error, :invalid_options}

  defp recorder_status(false, _stats), do: :unavailable

  defp recorder_status(true, %{pending: pending, dropped: dropped, max_pending: maximum}) do
    if dropped > 0 or pending >= maximum, do: :degraded, else: :available
  end

  defp status_label(:available), do: "Available"
  defp status_label(:degraded), do: "Degraded"

  @doc "Deletes expired history and rows beyond the configured global cap."
  @spec prune() :: {:ok, non_neg_integer()} | {:error, :unavailable}
  def prune, do: Reporter.prune()

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
         (is_nil(kind) or kind in ~w(request liveview job runtime)) and
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

  defp window_stats_query(from, to, minimum) do
    from(sample in Sample,
      where: sample.observed_at >= ^from and sample.observed_at < ^to,
      group_by: [sample.kind, sample.identity],
      having: count(sample.id) >= ^minimum,
      select: %{
        kind: sample.kind,
        identity: sample.identity,
        samples: count(sample.id),
        average: avg(sample.duration_ms),
        p95: fragment("percentile_cont(0.95) WITHIN GROUP (ORDER BY ?)", sample.duration_ms)
      }
    )
  end

  defp regression_rows(windows, threshold) do
    baseline =
      window_stats_query(windows.baseline_from, windows.baseline_to, windows.min_samples)

    current =
      window_stats_query(windows.current_from, windows.current_to, windows.min_samples)

    delta =
      dynamic(
        [current, baseline],
        fragment(
          "CASE WHEN ? = 0 THEN 0.0 ELSE ((? / ?) - 1) * 100 END",
          baseline.average,
          current.average,
          baseline.average
        )
      )

    from(current in subquery(current),
      join: baseline in subquery(baseline),
      on: baseline.kind == current.kind and baseline.identity == current.identity,
      where: current.p95 >= ^threshold,
      limit: ^windows.limit,
      select: %{
        kind: current.kind,
        identity: current.identity,
        baseline_samples: baseline.samples,
        current_samples: current.samples,
        baseline_average_ms: baseline.average,
        current_average_ms: current.average,
        current_p95_ms: current.p95,
        delta_percent:
          fragment(
            "CASE WHEN ? = 0 THEN 0.0 ELSE ((? / ?) - 1) * 100 END",
            baseline.average,
            current.average,
            baseline.average
          )
      }
    )
    |> order_by(^[desc: delta])
    |> order_by([current, _baseline], asc: current.kind, asc: current.identity)
    |> Repo.all()
    |> Enum.map(&normalize_regression(&1, threshold))
  end

  defp normalize_regression(row, threshold) do
    row
    |> Map.update!(:baseline_average_ms, &numeric_float/1)
    |> Map.update!(:current_average_ms, &numeric_float/1)
    |> Map.update!(:current_p95_ms, &numeric_float/1)
    |> Map.update!(:delta_percent, &(numeric_float(&1) |> Float.round(1)))
    |> Map.put(:slow?, numeric_float(row.current_p95_ms) >= threshold)
  end

  defp numeric_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric_float(value) when is_integer(value), do: value * 1.0
  defp numeric_float(value) when is_float(value), do: value
end
