[
  id: "base/settings",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_settings,
  namespace: Bilimbi.Base.Settings,
  dependencies: ["base/database", "base/module_registry"],
  migrations: "priv/repo/migrations",
  web: nil,
  schema_contract: Bilimbi.Base.Settings.SchemaContract,
  contribution_provider: Bilimbi.Base.Settings.Contributions
]
