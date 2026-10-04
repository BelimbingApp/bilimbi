defmodule Bilimbi.Base.Queue.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Queue.Migrations.CreateObanRuntime
  alias Bilimbi.Base.Repo

  @version 20_260_820_130_000

  # Oban verifies its tables when the supervised Queue runtime starts, which
  # is before any test_helper.exs runs, even under `testing: :manual`. Every
  # suite whose project boots Queue therefore creates the tables from its
  # `test` alias, before the application starts:
  #
  #     "run --no-start -e Bilimbi.Base.Queue.TestFixtures.ensure_runtime_tables!()"
  @spec ensure_runtime_tables!() :: :ok
  def ensure_runtime_tables! do
    Code.require_file(
      Application.app_dir(
        :bilimbi_base_queue,
        "priv/repo/migrations/20260820130000_create_base_queue_oban_runtime.exs"
      )
    )

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn repo ->
        Ecto.Migrator.run(repo, [{@version, CreateObanRuntime}], :up, all: true, log: false)
      end)

    :ok
  end
end
