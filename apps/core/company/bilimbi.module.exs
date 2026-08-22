[
  id: "core/company",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_company,
  namespace: Bilimbi.Core.Company,
  dependencies: [
    "base/authz",
    "base/datetime",
    "base/database",
    "base/module_registry",
    "base/principal_directory",
    "base/settings",
    "base/tenancy",
    "base/ui",
    "core/geonames"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_811_093_956 => :compatible_baseline,
    20_260_811_093_957 => :compatible_baseline
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Company.SchemaContract,
  contribution_provider: Bilimbi.Core.Company.Contributions,
  dev_seed: "priv/dev_seed.exs"
]
