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
    "base/tenancy",
    "core/company",
    "core/address"
  ],
  migrations: nil,
  schema_contract: nil
]
