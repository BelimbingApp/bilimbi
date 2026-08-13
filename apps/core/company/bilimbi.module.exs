[
  id: "core/company",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_company,
  namespace: Bilimbi.Core.Company,
  dependencies: ["base/database", "base/tenancy"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.Company.SchemaContract,
  contribution_provider: nil
]
