[
  id: "base/schedule",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_schedule,
  namespace: Bilimbi.Base.Schedule,
  dependencies: [
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/queue",
    "base/settings"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_813_114_301 => :compatible_baseline,
    20_260_821_100_001 => :bilimbi_only
  },
  web: nil,
  schema_contract: Bilimbi.Base.Schedule.SchemaContract,
  contribution_provider: Bilimbi.Base.Schedule.Contributions
]
