defmodule Bilimbi.Base.Schedule.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bilimbi_base_schedule, :scheduler_enabled, true) do
        [Bilimbi.Base.Schedule.Scheduler]
      else
        []
      end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Bilimbi.Base.Schedule.Supervisor
    )
  end
end
