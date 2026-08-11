import Config

database_options =
  case System.get_env("DATABASE_URL") do
    nil ->
      [
        username: System.get_env("PGUSER", "bilimbi"),
        password: System.get_env("PGPASSWORD", "bilimbi_dev_ca658ad7d8b5"),
        hostname: System.get_env("PGHOST", "localhost"),
        port: String.to_integer(System.get_env("PGPORT", "5433")),
        database: System.get_env("PGDATABASE", "bilimbi_dev")
      ]

    url ->
      [url: url]
  end

config :base,
       Bilimbi.Base.Repo,
       database_options ++
         [
           stacktrace: true,
           show_sensitive_data_on_connection_error: true,
           pool_size: 10
         ]

config :web, BilimbiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "JLKsxHDXUNLBR8WIgU06I8gkdAmnpr1yLlN9mLPa3XNGisoNFgS6GuVuABPfqtwQ",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:bilimbi_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:bilimbi_web, ~w(--watch)]}
  ]

config :web, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
