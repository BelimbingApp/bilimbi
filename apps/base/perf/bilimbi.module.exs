[
  id: "base/perf",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_perf,
  namespace: Bilimbi.Base.Perf,
  dependencies: [
    "base/authz",
    "base/dashboard",
    "base/database",
    "base/module_registry",
    "base/queue",
    "base/schedule",
    "base/settings",
    "base/ui"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_821_213_000 => :bilimbi_only},
  web: "priv/web_routes.exs",
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Perf.Contributions
]
