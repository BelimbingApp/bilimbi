defmodule Bilimbi.Base.Queue.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Queue.Migrations.CreateObanRuntime
  alias Bilimbi.Base.Repo

  @version 20_260_820_130_000

  def ensure_runtime_tables! do
    Code.require_file(
      Application.app_dir(
        :bilimbi_base_queue,
        "priv/repo/migrations/20260820130000_create_base_queue_oban_runtime.exs"
      )
    )

    Ecto.Migrator.run(Repo, [{@version, CreateObanRuntime}], :up, all: true, log: false)
  end
end
