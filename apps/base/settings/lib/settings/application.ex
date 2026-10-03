defmodule Bilimbi.Base.Settings.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Bilimbi.Base.Settings.Cache],
      strategy: :one_for_one,
      name: Bilimbi.Base.Settings.Supervisor
    )
  end
end
