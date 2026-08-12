import Config

config :bilimbi_base_database,
  ecto_repos: [Bilimbi.Base.Repo],
  generators: [timestamp_type: :utc_datetime]

config :bilimbi_base_database, Bilimbi.Base.Repo, migration_source: "bilimbi_schema_migrations"

config :web, BilimbiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BilimbiWeb.ErrorHTML, json: BilimbiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BilimbiWeb.PubSub,
  live_view: [signing_salt: "fXGTpqyR"]

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :esbuild,
  version: "0.25.4",
  bilimbi_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  bilimbi_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/web", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
