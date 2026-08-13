[
  id: "core/user_administration",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_user_administration,
  namespace: Bilimbi.Core.UserAdministration,
  dependencies: [
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/tenancy",
    "core/company",
    "core/user"
  ],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: nil
]
