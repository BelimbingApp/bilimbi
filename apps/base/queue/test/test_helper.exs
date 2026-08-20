Code.require_file(Path.expand("../../database/test/support/data_case.ex", __DIR__))

ExUnit.start()

alias Bilimbi.Base.Queue
alias Bilimbi.Base.Repo

migration_path =
  Path.expand(
    "../priv/repo/migrations/20260820130000_create_base_queue_oban_runtime.exs",
    __DIR__
  )

Code.require_file(migration_path)

Ecto.Migrator.run(
  Repo,
  [
    {20_260_820_130_000, Bilimbi.Base.Queue.Migrations.CreateObanRuntime}
  ],
  :up,
  all: true,
  log: false
)

unless Oban.whereis(Queue.oban_config()[:name]) do
  raise "the supervised Base Queue runtime did not start"
end

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
