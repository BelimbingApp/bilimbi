import Config

# Mix-time only: config/*.exs may load the discovery helpers that live
# beside ModuleRegistry. Runtime modules never call this file.
[discovery_file] =
  Path.wildcard(Path.expand("../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

Code.require_file(Path.expand("../mix/local_config.exs", __DIR__))
workspace_root = Path.expand("..", __DIR__)
local_config = Bilimbi.LocalConfig.load(workspace_root)
database_options = Bilimbi.LocalConfig.database_options(local_config)

config :bilimbi_base_database,
       Bilimbi.Base.Repo,
       database_options ++
         [
           stacktrace: true,
           show_sensitive_data_on_connection_error: false,
           pool_size: 10
         ]

https = Bilimbi.LocalConfig.https_options(local_config)

config :web, BilimbiWeb.Endpoint,
  # The development server uses the shared local Caddy ingress. Its HTTP
  # listener remains loopback-only; Caddy supplies the trusted HTTPS scheme.
  # Keep the canonical URL here so OAuth, exports and ordinary Mix commands
  # all agree, rather than relying on the request Host header.
  url: [scheme: "https", host: https.host, port: 443],
  http: [ip: {127, 0, 0, 1}, port: https.port],
  check_origin: ["https://#{https.host}"],
  force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: false, exclude: []],
  code_reloader: true,
  reloadable_apps:
    Bilimbi.Base.ModuleRegistry.MixDiscovery.reloadable_apps(Path.expand("..", __DIR__)),
  # Phoenix reloads a subset of Mix compilers. Collect changed module hooks
  # after Elixir and application metadata, before esbuild watches the entry.
  reloadable_compilers: [:phoenix_live_view, :gettext, :elixir, :app, :bilimbi_hooks],
  debug_errors: true,
  secret_key_base: "JLKsxHDXUNLBR8WIgU06I8gkdAmnpr1yLlN9mLPa3XNGisoNFgS6GuVuABPfqtwQ",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:bilimbi_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:bilimbi_web, ~w(--watch)]}
  ]

# Same bind the Endpoint uses. The shell reads this key, not :web, so
# base/ui never reaches across the application boundary for a display string.
config :bilimbi_base_ui, :listen_address, "127.0.0.1"

# Seals the actor on every tenant scope and signs jobs that act for a user
# (Bilimbi.Base.Tenancy.Authentication). Production derives it from
# SECRET_KEY_BASE in runtime.exs.
config :bilimbi_base_tenancy, :actor_secret, "dev-actor-secret-4hWq8Tn2Ks6Ym0Rb3Vc7Xe1Pz5Lg9Jd"

config :web, dev_routes: true
config :web, BilimbiWeb.Mailer, adapter: Swoosh.Adapters.Local
config :web, :mailer_sender, {"Bilimbi Development", "no-reply@bilimbi.local"}

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
