[
  id: "base/authz",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_authz,
  namespace: Bilimbi.Base.Authz,
  dependencies: ["base/database", "base/module_registry", "base/settings", "base/tenancy"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Base.Authz.SchemaContract,
  contribution_provider: Bilimbi.Base.Authz.Contributions
]
