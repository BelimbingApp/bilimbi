Code.ensure_loaded!(Bilimbi.Base.Tenancy.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Session.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Settings.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Audit.TestFixtures)
Code.ensure_loaded!(Bilimbi.Base.Perf.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Company.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Employee.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Geonames.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.Address.TestFixtures)
Code.ensure_loaded!(Bilimbi.Core.User.TestFixtures)

# An async test holds one sandbox connection for its whole run, and the
# LiveViews it mounts reach that connection through `$callers`. More
# concurrent cases than connections only queue on the pool until checkouts
# are dropped, so the case limit is the pool size (`config/test.exs`).
ExUnit.start(max_cases: Keyword.fetch!(Bilimbi.Base.Repo.config(), :pool_size))
Ecto.Adapters.SQL.Sandbox.mode(Bilimbi.Base.Repo, :manual)
