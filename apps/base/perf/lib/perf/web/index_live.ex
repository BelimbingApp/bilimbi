defmodule Bilimbi.Base.Perf.Web.IndexLive do
  @moduledoc "Authorized, bounded operator view of redacted performance history."

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Perf

  @page_sizes [25, 50, 100, 300]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Performance")
     |> assign(:diagnostics, Perf.diagnostics())
     |> assign(:filters, default_filters())
     |> assign(:total, 0)
     |> assign(:page_count, 1)
     |> stream(:samples, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    case Perf.list_samples(list_options(filters)) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(:filters, filters)
         |> assign(:total, page.total)
         |> assign(:page_count, max(ceil(page.total / filters.page_size), 1))
         |> assign(:diagnostics, Perf.diagnostics())
         |> stream(:samples, page.entries, reset: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:filters, filters)
         |> assign(:total, 0)
         |> assign(:page_count, 1)
         |> put_flash(:error, "Performance history is unavailable.")
         |> stream(:samples, [], reset: true)}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = parse_filters(params)
    {:noreply, push_patch(socket, to: filter_path(%{filters | page: 1}))}
  end

  def handle_event("previous", _params, socket) do
    filters = socket.assigns.filters
    {:noreply, push_patch(socket, to: filter_path(%{filters | page: max(filters.page - 1, 1)}))}
  end

  def handle_event("next", _params, socket) do
    filters = socket.assigns.filters
    page = min(filters.page + 1, socket.assigns.page_count)
    {:noreply, push_patch(socket, to: filter_path(%{filters | page: page}))}
  end

  defp default_filters, do: %{kind: "", outcome: "", identity: "", page: 1, page_size: 25}

  defp parse_filters(params) do
    %{
      kind: enum(params["kind"], ~w(request job runtime)),
      outcome: enum(params["outcome"], ~w(ok error cancelled discarded)),
      identity: bounded(params["identity"], 255),
      page: positive_integer(params["page"], 1),
      page_size: page_size(params["page_size"])
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

  defp human_status(:available), do: "Available"
  defp human_status(:unavailable), do: "Unavailable"
  defp human_status(:enabled), do: "Enabled"
  defp human_status(:disabled), do: "Disabled"
  defp human_status(_status), do: "Unknown"
end
