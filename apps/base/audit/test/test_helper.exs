Code.ensure_loaded!(Bilimbi.Base.Database.DataCase)
Code.ensure_loaded!(Bilimbi.Base.Tenancy.TestFixtures)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
