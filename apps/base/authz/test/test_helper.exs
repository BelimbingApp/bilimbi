Code.require_file(Path.expand("../../database/test/support/data_case.ex", __DIR__))

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
