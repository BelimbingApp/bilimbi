[
  id: "core/employee",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_employee,
  namespace: Bilimbi.Core.Employee,
  dependencies: [
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/principal_directory",
    "base/tenancy",
    "base/ui",
    "core/company"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_812_112_641 => :compatible_baseline,
    20_260_817_173_000 => :bilimbi_only,
    20_260_817_180_000 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Employee.SchemaContract,
  contribution_provider: Bilimbi.Core.Employee.Contributions,
  dev_seed: "priv/dev_seed.exs"
]
