defmodule Bilimbi.Base.Perf.Web.IndexLive do
  @moduledoc "Authorized, bounded operator view of redacted performance history."

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.UI.ListColumns

  @page_sizes [25, 50, 100, 300]
  @regression_columns [
    %{id: "identity", label: "Route / worker", type: :string},
    %{id: "baseline", label: "Baseline avg", type: :float, align: :right},
    %{id: "current", label: "Current p95", type: :float, align: :right},
    %{id: "change", label: "Change", type: :float, align: :right}
  ]
  @sample_columns [
    %{id: "observed_at", label: "Observed", type: :datetime},
    %{id: "kind", label: "Kind", type: :string},
    %{id: "identity", label: "Route / worker", type: :string},
    %{id: "outcome", label: "Outcome", type: :string},
    %{id: "duration", label: "Duration", type: :integer, align: :right},
    %{id: "database", label: "DB", type: :integer, align: :right}
  ]

  @write_guard_opt_out ~w(regressions_grid samples_grid)

  @impl true
  def mount(_params, _session, socket) do
    regressions = recent_regressions()

    {:ok,
     socket
     |> assign(:page_title, "Performance")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:diagnostics, Perf.diagnostics())
     |> assign(:regressions, regressions)
     |> assign(
       :regression_columns,
       ListColumns.mount("performance-regression-table", @regression_columns)
       |> ListColumns.load(regressions, & &1.identity)
     )
     |> assign(:sample_columns, ListColumns.mount("performance-sample-table", @sample_columns))
     |> assign(:filters, default_filters())
     |> assign(:filters_form, filters_form(default_filters()))
     |> assign(:samples_page, empty_page())
     |> assign(:total, 0)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    case Perf.list_samples(list_options(filters)) do
      {:ok, page} ->
        total_pages = total_pages(page.total, filters.page_size)

        cond do
          total_pages > 0 and filters.page > total_pages ->
            {:noreply, push_patch(socket, to: filter_path(%{filters | page: total_pages}))}

          total_pages == 0 and filters.page > 1 ->
            {:noreply, push_patch(socket, to: filter_path(%{filters | page: 1}))}

          true ->
            regressions = recent_regressions()

            {:noreply,
             socket
             |> assign(:filters, filters)
             |> assign(:filters_form, filters_form(filters))
             |> assign(:samples_page, samples_page(page, total_pages))
             |> assign(:total, page.total)
             |> assign(:diagnostics, Perf.diagnostics())
             |> assign(:regressions, regressions)
             |> assign(
               :regression_columns,
               ListColumns.load(socket.assigns.regression_columns, regressions, & &1.identity)
             )
             |> assign(
               :sample_columns,
               ListColumns.load(socket.assigns.sample_columns, page.entries, & &1.id)
             )}
        end

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:filters, filters)
         |> assign(:filters_form, filters_form(filters))
         |> assign(:samples_page, empty_page())
         |> assign(:total, 0)
         |> assign(:sample_columns, ListColumns.load(socket.assigns.sample_columns, [], & &1.id))
         |> put_flash(:error, "Performance history is unavailable.")}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = socket.assigns.filters |> merge_filter_params(params) |> parse_filters()
    {:noreply, push_patch(socket, to: filter_path(%{filters | page: 1}))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    filters = socket.assigns.filters
    {:noreply, push_patch(socket, to: filter_path(%{filters | page: positive_integer(page, 1)}))}
  end

  def handle_event("regressions_grid", params, socket) do
    case ListColumns.handle(socket.assigns.regression_columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :regression_columns, columns)}
      _other -> {:noreply, socket}
    end
  end

  def handle_event("samples_grid", params, socket) do
    case ListColumns.handle(socket.assigns.sample_columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :sample_columns, columns)}
      _other -> {:noreply, socket}
    end
  end

  defp default_filters, do: %{kind: "", outcome: "", identity: "", page: 1, page_size: 25}

  defp parse_filters(params) do
    %{
      kind: enum(params["kind"], ~w(request liveview job runtime)),
      outcome: enum(params["outcome"], ~w(ok error cancelled discarded)),
      identity: bounded(params["identity"], 255),
      page: positive_integer(params["page"], 1),
      page_size: page_size(params["page_size"] || params["perPage"])
    }
  end

  defp merge_filter_params(filters, params) do
    %{
      "kind" => Map.get(params, "kind", filters.kind),
      "outcome" => Map.get(params, "outcome", filters.outcome),
      "identity" => Map.get(params, "identity", filters.identity),
      "page" => Map.get(params, "page", filters.page),
      "page_size" => Map.get(params, "page_size") || Map.get(params, "perPage", filters.page_size)
    }
  end

  defp list_options(filters) do
    [page: filters.page, page_size: filters.page_size]
    |> maybe_put(:kind, filters.kind)
    |> maybe_put(:outcome, filters.outcome)
    |> maybe_put(:identity, filters.identity)
  end

  defp filter_path(filters) do
    query =
      %{
        "kind" => filters.kind,
        "outcome" => filters.outcome,
        "identity" => filters.identity,
        "page" => filters.page,
        "page_size" => filters.page_size
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    "/system/performance?" <> URI.encode_query(query)
  end

  defp maybe_put(options, _key, ""), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
  defp enum(value, values), do: if(value in values, do: value, else: "")

  defp bounded(value, maximum) when is_binary(value) do
    value |> String.trim() |> String.slice(0, maximum)
  end

  defp bounded(_value, _maximum), do: ""

  defp positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> fallback
    end
  end

  defp positive_integer(_value, fallback), do: fallback

  defp page_size(value) do
    size = positive_integer(value, 25)
    if size in @page_sizes, do: size, else: 25
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total, page_size), do: ceil(total / page_size)

  defp samples_page(page, total_pages) do
    %{
      entries: page.entries,
      page: page.page,
      page_size: page.page_size,
      total_entries: page.total,
      total_pages: total_pages
    }
  end

  defp empty_page do
    %{entries: [], page: 1, page_size: 25, total_entries: 0, total_pages: 0}
  end

  defp filters_form(filters) do
    to_form(
      %{
        "kind" => filters.kind,
        "outcome" => filters.outcome,
        "identity" => filters.identity,
        "perPage" => filters.page_size
      },
      as: :filters
    )
  end

  defp recent_regressions do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Perf.regressions(
           baseline_from: DateTime.add(now, -2, :hour),
           baseline_to: DateTime.add(now, -1, :hour),
           current_from: DateTime.add(now, -1, :hour),
           current_to: now,
           min_samples: 5,
           limit: 10
         ) do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  defp human_status(:available), do: "Available"
  defp human_status(:unavailable), do: "Unavailable"
  defp human_status(:degraded), do: "Degraded"
  defp human_status(:enabled), do: "Enabled"
  defp human_status(:disabled), do: "Disabled"
  defp human_status(_status), do: "Unknown"
end
