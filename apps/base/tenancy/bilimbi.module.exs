[
  id: "base/tenancy",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_tenancy,
  namespace: Bilimbi.Base.Tenancy,
  dependencies: ["base/database"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Base.Tenancy.SchemaContract,
  contribution_provider: nil
]
