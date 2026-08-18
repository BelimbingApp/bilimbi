[
  id: "base/database",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_database,
  namespace: Bilimbi.Base.Database,
  dependencies: ["base/dashboard", "base/module_registry"],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Database.Contributions
]
