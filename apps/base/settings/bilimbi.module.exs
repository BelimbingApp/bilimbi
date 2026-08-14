[
  id: "base/settings",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_settings,
  namespace: Bilimbi.Base.Settings,
  dependencies: ["base/database", "base/module_registry", "base/ui"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_811_093_952 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Settings.SchemaContract,
  contribution_provider: Bilimbi.Base.Settings.Contributions
]
