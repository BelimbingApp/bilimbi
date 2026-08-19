Code.require_file(Path.expand("../../../base/database/test/support/data_case.ex", __DIR__))
Code.require_file(Path.expand("../../../base/settings/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../../base/tenancy/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../../base/audit/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../../base/session/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../../base/authz/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../geonames/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../company/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../employee/test/support/test_fixtures.ex", __DIR__))

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)

pubsub_server = Bilimbi.Core.User.TestPubSub
Application.put_env(:bilimbi_core_user, :pubsub_server, pubsub_server)

unless Process.whereis(pubsub_server) do
  Supervisor.start_link([{Phoenix.PubSub, name: pubsub_server}], strategy: :one_for_one)
end
