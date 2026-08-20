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

{:ok, oban_pid} = Oban.start_link(Queue.oban_config())
Process.unlink(oban_pid)

ExUnit.after_suite(fn _result ->
  if Process.alive?(oban_pid), do: Supervisor.stop(oban_pid)
end)

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
