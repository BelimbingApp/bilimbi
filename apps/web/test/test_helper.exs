Code.require_file(Path.expand("../../base/tenancy/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../base/session/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../base/authz/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../core/company/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../core/employee/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../core/user/test/support/test_fixtures.ex", __DIR__))

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
