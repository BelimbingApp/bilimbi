defmodule Bilimbi.Base.Queue.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      children(Bilimbi.Base.Queue.oban_config()),
      strategy: :one_for_one,
      name: Bilimbi.Base.Queue.Supervisor
    )
  end

  @doc false
  def children(config), do: [{Oban, config}]
end
