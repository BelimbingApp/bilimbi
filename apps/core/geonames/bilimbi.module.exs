[
  id: "core/geonames",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_geonames,
  namespace: Bilimbi.Core.Geonames,
  dependencies: ["base/database"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.Geonames.SchemaContract
]
