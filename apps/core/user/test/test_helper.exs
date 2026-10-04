Code.ensure_loaded!(Bilimbi.Base.Database.DataCase)
Code.ensure_loaded!(Bilimbi.Base.Settings.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Tenancy.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Audit.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Session.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Geonames.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Company.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Employee.TestFixtures)

ExUnit.start()
Bilimbi.Base.Queue.TestFixtures.ensure_runtime_tables!()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)

pubsub_server = Bilimbi.Core.User.TestPubSub
Application.put_env(:bilimbi_core_user, :pubsub_server, pubsub_server)

unless Process.whereis(pubsub_server) do
  Supervisor.start_link([{Phoenix.PubSub, name: pubsub_server}], strategy: :one_for_one)
end
