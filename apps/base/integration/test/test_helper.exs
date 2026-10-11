Code.ensure_loaded!(Bilimbi.Base.Database.DataCase)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
