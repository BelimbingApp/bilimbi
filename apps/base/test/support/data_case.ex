defmodule Bilimbi.Base.DataCase do
  @moduledoc """
  SQL sandbox setup shared by umbrella tests.

  Business fixtures remain with their owning Core module rather than teaching
  Base about business tables.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Bilimbi.Base.Repo

      import Ecto.Query
      import Bilimbi.Base.DataCase
    end
  end

  setup tags do
    owner =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Bilimbi.Base.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    :ok
  end
end
