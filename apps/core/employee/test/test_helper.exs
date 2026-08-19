Code.require_file(Path.expand("../../../base/database/test/support/data_case.ex", __DIR__))
Code.require_file(Path.expand("../../../base/tenancy/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../geonames/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../company/test/support/test_fixtures.ex", __DIR__))

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
