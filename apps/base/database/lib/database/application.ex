defmodule Bilimbi.Base.Database.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Bilimbi.Base.Repo, Bilimbi.Base.Database.ConsoleRepo],
      strategy: :one_for_one,
      name: Bilimbi.Base.Database.Supervisor
    )
  end
end
