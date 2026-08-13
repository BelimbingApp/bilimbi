[
  id: "core/user",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_user,
  namespace: Bilimbi.Core.User,
  dependencies: [
    "base/database",
    "base/module_registry",
    "base/tenancy",
    "core/company",
    "core/employee"
  ],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.User.SchemaContract,
  contribution_provider: Bilimbi.Core.User.Contributions
]
