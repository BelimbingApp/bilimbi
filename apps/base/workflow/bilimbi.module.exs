[
  id: "base/workflow",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_workflow,
  namespace: Bilimbi.Base.Workflow,
  dependencies: [
    "base/audit",
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/tenancy"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_261_003_090_000 => :compatible_baseline,
    20_261_003_091_000 => :compatible_baseline,
    20_261_003_092_000 => :compatible_baseline,
    20_261_003_100_000 => :bilimbi_only
  },
  web: nil,
  schema_contract: Bilimbi.Base.Workflow.SchemaContract,
  contribution_provider: nil,
  dev_seed: nil
]
