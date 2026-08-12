[
  id: "core/address",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_address,
  namespace: Bilimbi.Core.Address,
  dependencies: ["base/database", "base/tenancy", "core/company"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.Address.SchemaContract
]
