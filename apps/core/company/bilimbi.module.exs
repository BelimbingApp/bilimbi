[
  id: "core/company",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_company,
  namespace: Bilimbi.Core.Company,
  dependencies: ["base/authz", "base/database", "base/module_registry", "base/tenancy"],
  migrations: "priv/repo/migrations",
  web: nil,
  schema_contract: Bilimbi.Core.Company.SchemaContract,
  contribution_provider: Bilimbi.Core.Company.Contributions
]
