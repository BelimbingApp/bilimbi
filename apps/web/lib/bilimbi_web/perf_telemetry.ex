defmodule BilimbiWeb.PerfTelemetry do
  @moduledoc false

  use GenServer

  @handler_id "bilimbi-web-perf"
  @events [
    [:phoenix, :router_dispatch, :start],
    [:phoenix, :router_dispatch, :stop],
    [:phoenix, :router_dispatch, :exception],
    [:bilimbi, :repo, :query]
  ]

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    :telemetry.detach(@handler_id)

    :ok =
      :telemetry.attach_many(
        @handler_id,
        @events,
        &Bilimbi.Base.Perf.handle_event/4,
        make_ref()
      )

    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end
end
