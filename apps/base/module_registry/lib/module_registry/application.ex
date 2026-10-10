defmodule Bilimbi.Base.ModuleRegistry.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Processes that must not read the contribution snapshot before the
      # deployment installs it register here; see
      # `ContributionRegistry.subscribe_installed/0`.
      {Registry,
       keys: :duplicate, name: Bilimbi.Base.ModuleRegistry.ContributionRegistry.Subscribers}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Bilimbi.Base.ModuleRegistry.Supervisor
    )
  end
end
