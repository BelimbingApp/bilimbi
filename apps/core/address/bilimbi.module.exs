[
  id: "core/address",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_address,
  namespace: Bilimbi.Core.Address,
  dependencies: [
    "base/authz",
    "base/database",
    "base/locale",
    "base/module_registry",
    "base/tenancy",
    "base/ui",
    "core/company",
    "core/employee",
    "core/geonames"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_812_103_809 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Address.SchemaContract,
  contribution_provider: Bilimbi.Core.Address.Contributions
]
