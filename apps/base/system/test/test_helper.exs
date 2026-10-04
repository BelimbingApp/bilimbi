Code.ensure_loaded!(Bilimbi.Base.Database.DataCase)

ExUnit.start()
Bilimbi.Base.Queue.TestFixtures.ensure_runtime_tables!()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
