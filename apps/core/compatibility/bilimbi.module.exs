[
  id: "core/compatibility",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_compatibility,
  namespace: Bilimbi.Core.Compatibility,
  dependencies: [
    "base/database",
    "base/module_registry",
    "base/authz",
    "base/settings",
    "base/tenancy",
    "core/company",
    "core/geonames",
    "core/address",
    "core/employee",
    "core/user"
  ],
  migrations: nil,
  schema_contract: nil,
  contribution_provider: nil
]
