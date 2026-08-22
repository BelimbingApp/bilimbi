[
  id: "core/geonames",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_geonames,
  namespace: Bilimbi.Core.Geonames,
  dependencies: ["base/authz", "base/database", "base/module_registry", "base/ui"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_812_103_801 => :compatible_baseline,
    20_260_820_143_500 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Geonames.SchemaContract,
  contribution_provider: Bilimbi.Core.Geonames.Contributions,
  dev_seed: nil
]
