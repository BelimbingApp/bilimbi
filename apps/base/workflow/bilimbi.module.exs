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
    "base/tenancy",
    "base/ui"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_261_003_090_000 => :compatible_baseline,
    20_261_003_091_000 => :compatible_baseline,
    20_261_003_092_000 => :compatible_baseline,
    20_261_003_100_000 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Workflow.SchemaContract,
  contribution_provider: Bilimbi.Base.Workflow.Contributions,
  dev_seed: nil
]
