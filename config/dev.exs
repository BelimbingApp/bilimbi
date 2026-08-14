import Config

# Mix-time only: config/*.exs may load the discovery helpers that live
# beside ModuleRegistry. Runtime modules never call this file.
discovery_files =
  Path.wildcard(Path.expand("../apps/base/*/mix/module_discovery.exs", __DIR__))

discovery_file =
  case discovery_files do
    [path] ->
      path

    [] ->
      raise "expected apps/base/*/mix/module_discovery.exs, found none"

    paths ->
      raise "expected one module_discovery.exs, found #{inspect(paths)}"
  end

Code.require_file(discovery_file)

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

config :bilimbi_base_database,
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
  reloadable_apps:
    Bilimbi.Base.ModuleRegistry.MixDiscovery.reloadable_apps(Path.expand("..", __DIR__)),
  debug_errors: true,
  secret_key_base: "JLKsxHDXUNLBR8WIgU06I8gkdAmnpr1yLlN9mLPa3XNGisoNFgS6GuVuABPfqtwQ",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:bilimbi_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:bilimbi_web, ~w(--watch)]}
  ]

# Same bind the Endpoint uses. The shell reads this key, not :web, so
# base/ui never reaches across the application boundary for a display string.
config :bilimbi_base_ui, :listen_address, "127.0.0.1"

config :web, dev_routes: true
config :web, BilimbiWeb.Mailer, adapter: Swoosh.Adapters.Local

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
