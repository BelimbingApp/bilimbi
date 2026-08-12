defmodule Bilimbi.Base.Database.DataCase do
  @moduledoc """
  Shared SQL sandbox case for tests that use Bilimbi's one Ecto Repo.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Bilimbi.Base.Repo

      import Bilimbi.Base.Database.DataCase
      import Ecto.Changeset
      import Ecto.Query
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

  @doc false
  def temporary_schema! do
    case Ecto.Adapters.SQL.query!(
           Bilimbi.Base.Repo,
           "SELECT nspname FROM pg_namespace WHERE oid = pg_my_temp_schema()",
           []
         ).rows do
      [[schema]] when is_binary(schema) -> schema
      _rows -> raise "the current sandbox connection has no temporary schema"
    end
  end
end
