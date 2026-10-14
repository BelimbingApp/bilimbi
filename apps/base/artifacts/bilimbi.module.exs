[
  id: "base/artifacts",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_artifacts,
  namespace: Bilimbi.Base.Artifacts,
  dependencies: [
    "base/audit",
    "base/database",
    "base/module_registry",
    "base/queue",
    "base/settings",
    "base/tenancy"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_930_120_000 => :bilimbi_only,
    20_261_013_090_000 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Artifacts.SchemaContract,
  contribution_provider: Bilimbi.Base.Artifacts.Contributions,
  dev_seed: nil
]
