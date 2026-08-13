[
  id: "core/geonames",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_geonames,
  namespace: Bilimbi.Core.Geonames,
  dependencies: ["base/database", "base/module_registry", "base/ui"],
  migrations: "priv/repo/migrations",
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Geonames.SchemaContract,
  contribution_provider: Bilimbi.Core.Geonames.Contributions
]
