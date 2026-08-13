[
  id: "base/audit",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_audit,
  namespace: Bilimbi.Base.Audit,
  dependencies: ["base/database", "base/tenancy"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Base.Audit.SchemaContract,
  contribution_provider: nil
]
