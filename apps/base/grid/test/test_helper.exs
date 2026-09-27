Code.require_file(Path.expand("../../database/test/support/data_case.ex", __DIR__))
Code.require_file(Path.expand("../../tenancy/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../settings/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../authz/test/support/test_fixtures.ex", __DIR__))

ExUnit.start(exclude: [:performance])
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
