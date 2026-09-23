import Config

config :bilimbi_base_database,
  ecto_repos: [Bilimbi.Base.Repo],
  generators: [timestamp_type: :utc_datetime]

config :bilimbi_base_database, Bilimbi.Base.Repo, migration_source: "bilimbi_schema_migrations"

config :bilimbi_base_queue,
  name: Bilimbi.Base.Queue.Oban,
  repo: Bilimbi.Base.Repo,
  prefix: "public",
  queues: [default: 10],
  plugins: [{Oban.Plugins.Pruner, max_age: 604_800}],
  shutdown_grace_period: 15_000

config :web, BilimbiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BilimbiWeb.ErrorHTML, json: BilimbiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BilimbiWeb.PubSub,
  live_view: [signing_salt: "fXGTpqyR"]

config :bilimbi_core_user,
  pubsub_server: BilimbiWeb.PubSub

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

# ADR 0013 (#630): repo-level mutation capture. Base Database defines the
# seam; Base Audit implements the canonical row policy; the workspace wires
# them here so no compile-time edge crosses the module graph.
config :bilimbi_base_database, write_capture: Bilimbi.Base.Audit.MutationCapture

# Every database console command — succeeded, refused, or failed — is one
# audit action. The console runs on the application's own connection with
# no login of its own; the record is its control. Same seam shape as above.
config :bilimbi_base_database, console_capture: Bilimbi.Base.Audit.ConsoleCapture

# ADR 0013 (#785): the port of Belimbing's `audit.exclude_models`. Capture
# is comprehensive by default, so silence is explicit and justified here,
# one entry at a time. A schema belongs on this list only when *nothing*
# written to it is an actor's business decision; where the same table holds
# both, the machine-only call site wraps itself in
# `Bilimbi.Base.Database.WriteCapture.without_capture/1` instead, and says
# why there.
config :bilimbi_base_audit,
  exclude_schemas: [
    # One row per authorization decision the platform evaluates. The
    # decision log is its own operational surface with its own retention;
    # auditing writes to it records nothing about who changed anything.
    Bilimbi.Base.Authz.DecisionLog,

    # Performance samples: machine measurements, written on a timer and
    # pruned on a timer.
    Bilimbi.Base.Perf.Sample,

    # Scheduler state. An occurrence moves between claimed, running and
    # finished as the job runs; a run is the history of one execution.
    # Neither is an actor's decision — pausing a job is, and
    # `Bilimbi.Base.Schedule.Suppression` is deliberately absent from this
    # list so suppress and unsuppress both leave a row.
    Bilimbi.Base.Schedule.Occurrence,
    Bilimbi.Base.Schedule.Run,

    # Geonames reference data, imported and re-imported wholesale from
    # upstream files. The largest import in the product is 34,140 city
    # rows; auditing it would bury the trail in place names nobody
    # decided.
    Bilimbi.Core.Geonames.Country,
    Bilimbi.Core.Geonames.Admin1,
    Bilimbi.Core.Geonames.City,
    Bilimbi.Core.Geonames.Postcode,

    # Ecto's own migration ledger. `bilimbi_schema_migrations` records
    # which migrations ran; a migration is not an actor's mutation, and
    # ADR 0002 keeps the ledger outside business data entirely.
    Ecto.Migration.SchemaMigration,

    # Password-reset tokens: credential machinery with its own lifecycle.
    # The password change they complete is audited on the user row; the
    # token rows are secrets, and the trail is better off not holding
    # their metadata at all.
    Bilimbi.Core.User.PasswordResetToken
  ]

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
  metadata: [:request_id, :schedule_key, :schedule_owner, :schedule_reason, :schedule_source]

config :phoenix, :json_library, Jason

# Route manifest lives at `_build/<env>/bilimbi_routes.exs`. Capture the Mix
# environment here so application modules never call `Mix.env/0` (Dialyzer).
config :bilimbi_base_ui, :mix_env, config_env()
config :bilimbi_base_ui, :app_version, Mix.Project.config()[:version]
config :web, :mix_env, config_env()

import_config "#{config_env()}.exs"
