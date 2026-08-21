defmodule BilimbiWeb.PerfTelemetry do
  @moduledoc false

  use GenServer

  @handler_id "bilimbi-web-perf"
  @events [
    [:phoenix, :router_dispatch, :start],
    [:phoenix, :router_dispatch, :stop],
    [:phoenix, :router_dispatch, :exception],
    [:phoenix, :live_view, :handle_event, :start],
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :live_view, :handle_event, :exception],
    [:phoenix, :live_view, :handle_params, :start],
    [:phoenix, :live_view, :handle_params, :stop],
    [:phoenix, :live_view, :handle_params, :exception],
    [:bilimbi, :base, :repo, :query]
  ]

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc false
  def attach_handlers do
    detach_handlers()

    :telemetry.attach_many(
      @handler_id,
      @events,
      &Bilimbi.Base.Perf.handle_event/4,
      make_ref()
    )
  end

  @doc false
  def detach_handlers do
    :telemetry.detach(@handler_id)
    :ok
  end

  @impl true
  def init(_options) do
    if instrumentation_enabled?(), do: attach_handlers(), else: detach_handlers()

    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    detach_handlers()
  end

  defp instrumentation_enabled? do
    Application.get_env(:bilimbi_base_perf, :instrumentation_enabled, true)
  end
end
