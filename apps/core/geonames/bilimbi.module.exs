[
  id: "core/geonames",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_geonames,
  namespace: Bilimbi.Core.Geonames,
  dependencies: ["base/database", "base/module_registry"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.Geonames.SchemaContract,
  contribution_provider: Bilimbi.Core.Geonames.Contributions
]
