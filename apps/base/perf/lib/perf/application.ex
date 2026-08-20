defmodule Bilimbi.Base.Perf.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      [Bilimbi.Base.Perf.Reporter, Bilimbi.Base.Perf.RuntimeSampler],
      strategy: :one_for_one,
      name: Bilimbi.Base.Perf.Supervisor
    )
  end
end
