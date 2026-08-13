[
  id: "base/tenancy",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_tenancy,
  namespace: Bilimbi.Base.Tenancy,
  dependencies: ["base/database", "base/module_registry"],
  migrations: "priv/repo/migrations",
  web: nil,
  schema_contract: Bilimbi.Base.Tenancy.SchemaContract,
  contribution_provider: Bilimbi.Base.Tenancy.Contributions
]
