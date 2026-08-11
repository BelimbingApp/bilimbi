defmodule Bilimbi.Base.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Bilimbi.Base.Repo]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Bilimbi.Base.Supervisor
    )
  end
end
