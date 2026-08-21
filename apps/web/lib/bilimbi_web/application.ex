defmodule BilimbiWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Bilimbi.Base.ModuleRegistry.ContributionRegistry.install!()

    children = [
      BilimbiWeb.Telemetry,
      BilimbiWeb.PerfTelemetry,
      {DNSCluster, query: Application.get_env(:web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BilimbiWeb.PubSub},
      BilimbiWeb.RateLimit,
      BilimbiWeb.Endpoint
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: BilimbiWeb.Supervisor
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    BilimbiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
