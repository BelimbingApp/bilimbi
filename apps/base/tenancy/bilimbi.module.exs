[
  id: "base/tenancy",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_tenancy,
  namespace: Bilimbi.Base.Tenancy,
  dependencies: ["base/database", "base/module_registry", "base/ui"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_811_093_951 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Tenancy.SchemaContract,
  contribution_provider: Bilimbi.Base.Tenancy.Contributions,
  dev_seed: nil
]
