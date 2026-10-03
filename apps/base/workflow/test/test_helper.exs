Code.ensure_loaded!(Bilimbi.Base.Database.DataCase)
Code.ensure_loaded!(Bilimbi.Base.Tenancy.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Audit.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
