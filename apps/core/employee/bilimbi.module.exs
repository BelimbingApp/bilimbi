[
  id: "core/employee",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_employee,
  namespace: Bilimbi.Core.Employee,
  dependencies: ["base/database", "base/module_registry", "base/tenancy", "core/company"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_812_112_641 => :compatible_baseline},
  web: nil,
  schema_contract: Bilimbi.Core.Employee.SchemaContract,
  contribution_provider: Bilimbi.Core.Employee.Contributions
]
