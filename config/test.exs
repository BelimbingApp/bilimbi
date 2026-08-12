import Config

config :bilimbi_base_database, Bilimbi.Base.Repo,
  username: System.get_env("PGUSER", "bilimbi"),
  password: System.get_env("PGPASSWORD", "bilimbi_dev_ca658ad7d8b5"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5433")),
  database: "bilimbi_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :web, BilimbiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MRty3402yaFk5Y1BBT0o3cqcXutsDD8jd0H3eALvFlKUJsWJjN609o5+P3RE94JQ",
  server: false

config :swoosh, :api_client, false
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true
config :phoenix, sort_verified_routes_query_params: true
