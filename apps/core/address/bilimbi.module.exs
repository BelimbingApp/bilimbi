[
  id: "core/address",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_address,
  namespace: Bilimbi.Core.Address,
  dependencies: ["base/database", "base/tenancy", "core/company", "core/geonames"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.Address.SchemaContract
]
