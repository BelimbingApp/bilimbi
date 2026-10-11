defmodule Bilimbi.Base.Artifacts.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Bilimbi.Base.Artifacts.PDF.Tokens],
      strategy: :one_for_one,
      name: Bilimbi.Base.Artifacts.Supervisor
    )
  end
end
