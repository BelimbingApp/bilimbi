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
    "base/settings",
    "base/tenancy"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_930_120_000 => :bilimbi_only},
  web: nil,
  schema_contract: Bilimbi.Base.Artifacts.SchemaContract,
  contribution_provider: Bilimbi.Base.Artifacts.Contributions,
  dev_seed: nil
]
